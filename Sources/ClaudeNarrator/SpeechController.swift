import AVFAudio
import Foundation

@MainActor
final class SpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate,
  AVAudioPlayerDelegate
{
  struct NeuralVoice: Identifiable, Hashable {
    let id: String
    let displayName: String
  }

  static let neuralVoices = [
    NeuralVoice(id: "zh-CN-XiaoxiaoNeural", displayName: "晓晓 · 温暖女声"),
    NeuralVoice(id: "zh-CN-XiaoyiNeural", displayName: "晓伊 · 明快女声"),
    NeuralVoice(id: "zh-CN-YunxiNeural", displayName: "云希 · 自然男声"),
    NeuralVoice(id: "zh-CN-YunyangNeural", displayName: "云扬 · 专业男声"),
  ]

  enum PlaybackState: Equatable {
    case idle
    case synthesizing
    case speaking
    case paused
  }

  private enum ActiveEngine {
    case neural
    case system
  }

  @Published private(set) var playbackState: PlaybackState = .idle
  @Published private(set) var lastOriginalText = ""
  @Published private(set) var lastSpokenText = ""
  @Published private(set) var lastProjectName = ""
  @Published private(set) var voiceModeDescription = "自然神经语音"
  @Published var isMuted: Bool {
    didSet { UserDefaults.standard.set(isMuted, forKey: Keys.muted) }
  }
  @Published var ratePercent: Double {
    didSet {
      UserDefaults.standard.set(ratePercent, forKey: Keys.rate)
      audioPlayer?.rate = Float(ratePercent / 100)
    }
  }
  @Published var useNaturalVoice: Bool {
    didSet { UserDefaults.standard.set(useNaturalVoice, forKey: Keys.useNaturalVoice) }
  }
  @Published var neuralVoiceID: String {
    didSet { UserDefaults.standard.set(neuralVoiceID, forKey: Keys.neuralVoiceID) }
  }

  private let systemSynthesizer = AVSpeechSynthesizer()
  private(set) var audioPlayer: AVAudioPlayer?
  private var synthesisProcess: Process?
  private var synthesisToken = UUID()
  private var activeEngine: ActiveEngine?
  private var lastAudioURL: URL?

  override init() {
    isMuted = UserDefaults.standard.bool(forKey: Keys.muted)

    let savedRate = UserDefaults.standard.double(forKey: Keys.rate)
    ratePercent = savedRate == 0 ? 110 : min(max(savedRate, 70), 150)

    if UserDefaults.standard.object(forKey: Keys.useNaturalVoice) == nil {
      useNaturalVoice = true
    } else {
      useNaturalVoice = UserDefaults.standard.bool(forKey: Keys.useNaturalVoice)
    }

    let savedVoice = UserDefaults.standard.string(forKey: Keys.neuralVoiceID)
    neuralVoiceID =
      Self.neuralVoices.contains(where: { $0.id == savedVoice })
      ? savedVoice! : Self.neuralVoices[0].id

    super.init()
    systemSynthesizer.delegate = self
  }

  var naturalVoiceAvailable: Bool {
    edgeTTSExecutableURL != nil
  }

  func prepare(original: String, projectPath: String?) {
    // A newly received reply must never replay the previous reply's audio.
    if let lastAudioURL { try? FileManager.default.removeItem(at: lastAudioURL) }
    lastAudioURL = nil
    lastOriginalText = original
    if let projectPath, !projectPath.isEmpty {
      lastProjectName = URL(fileURLWithPath: projectPath).lastPathComponent
    }
  }

  func store(spokenText: String) {
    lastSpokenText = spokenText
  }

  func speak(_ text: String) {
    let safeText = SpeechTextProcessor.makeSpeechSafe(text)
    guard !safeText.isEmpty else { return }
    lastSpokenText = safeText
    guard !isMuted else { return }

    stopCurrentPlayback(setIdle: false)
    if useNaturalVoice, let executableURL = edgeTTSExecutableURL {
      synthesizeNeuralSpeech(safeText, executableURL: executableURL)
    } else {
      speakWithSystemVoice(safeText)
    }
  }

  func togglePauseResume() {
    switch playbackState {
    case .speaking:
      switch activeEngine {
      case .neural:
        audioPlayer?.pause()
        playbackState = .paused
      case .system:
        if systemSynthesizer.pauseSpeaking(at: .immediate) {
          playbackState = .paused
        }
      case nil:
        break
      }
    case .paused:
      guard !isMuted else { return }
      switch activeEngine {
      case .neural:
        if audioPlayer?.play() == true {
          playbackState = .speaking
        }
      case .system:
        if systemSynthesizer.continueSpeaking() {
          playbackState = .speaking
        }
      case nil:
        break
      }
    case .idle, .synthesizing:
      break
    }
  }

  func stop() {
    stopCurrentPlayback(setIdle: true)
  }

  func replay() {
    guard !lastSpokenText.isEmpty, !isMuted else { return }
    if useNaturalVoice, let lastAudioURL,
      FileManager.default.fileExists(atPath: lastAudioURL.path)
    {
      stopCurrentPlayback(setIdle: false)
      playNeuralAudio(at: lastAudioURL, fallbackText: lastSpokenText)
    } else {
      speak(lastSpokenText)
    }
  }

  func toggleMute() {
    setMuted(!isMuted)
  }

  func setMuted(_ muted: Bool) {
    isMuted = muted
    if muted {
      switch playbackState {
      case .speaking:
        togglePauseResume()
      case .synthesizing:
        stopCurrentPlayback(setIdle: true)
      case .idle, .paused:
        break
      }
    }
  }

  private func synthesizeNeuralSpeech(_ text: String, executableURL: URL) {
    let token = UUID()
    synthesisToken = token
    playbackState = .synthesizing
    voiceModeDescription = "正在生成自然神经语音"

    guard let outputURL = neuralAudioCacheURL(token: token) else {
      speakWithSystemVoice(text)
      return
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = [
      "--voice", neuralVoiceID,
      // Cache neutral-speed audio; the player applies the current speed live.
      "--rate", "+0%",
      "--text", text,
      "--write-media", outputURL.path,
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { [weak self] completedProcess in
      let succeeded = completedProcess.terminationStatus == 0
      Task { @MainActor in
        self?.completeNeuralSynthesis(
          token: token,
          succeeded: succeeded,
          outputURL: outputURL,
          fallbackText: text
        )
      }
    }
    synthesisProcess = process

    do {
      try process.run()
    } catch {
      synthesisProcess = nil
      speakWithSystemVoice(text)
    }
  }

  private func completeNeuralSynthesis(
    token: UUID,
    succeeded: Bool,
    outputURL: URL,
    fallbackText: String
  ) {
    guard token == synthesisToken else {
      try? FileManager.default.removeItem(at: outputURL)
      return
    }
    synthesisProcess = nil
    guard !isMuted else {
      playbackState = .idle
      return
    }

    let hasAudio = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0
    guard succeeded, hasAudio > 0 else {
      try? FileManager.default.removeItem(at: outputURL)
      speakWithSystemVoice(fallbackText)
      return
    }

    if let previousURL = lastAudioURL, previousURL != outputURL {
      try? FileManager.default.removeItem(at: previousURL)
    }
    lastAudioURL = outputURL
    playNeuralAudio(at: outputURL, fallbackText: fallbackText)
  }

  func playNeuralAudio(at url: URL, fallbackText: String) {
    do {
      let player = try AVAudioPlayer(contentsOf: url)
      player.delegate = self
      player.enableRate = true
      player.rate = Float(ratePercent / 100)
      player.prepareToPlay()
      audioPlayer = player
      activeEngine = .neural
      voiceModeDescription = "自然神经语音"
      if player.play() {
        playbackState = .speaking
      } else {
        speakWithSystemVoice(fallbackText)
      }
    } catch {
      speakWithSystemVoice(fallbackText)
    }
  }

  private func speakWithSystemVoice(_ text: String) {
    activeEngine = .system
    voiceModeDescription = "系统语音（离线回退）"
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = preferredSystemVoice()
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(ratePercent / 100)
    utterance.pitchMultiplier = 1.0
    utterance.volume = 1.0
    systemSynthesizer.speak(utterance)
    playbackState = .speaking
  }

  private func stopCurrentPlayback(setIdle: Bool) {
    synthesisToken = UUID()
    if synthesisProcess?.isRunning == true {
      synthesisProcess?.terminate()
    }
    synthesisProcess = nil

    activeEngine = nil
    audioPlayer?.stop()
    audioPlayer = nil
    systemSynthesizer.stopSpeaking(at: .immediate)

    if setIdle {
      playbackState = .idle
    }
  }

  private var edgeTTSExecutableURL: URL? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let candidates = [
      home.appendingPathComponent(".claude/hooks/tts-venv/bin/edge-tts"),
      URL(fileURLWithPath: "/opt/homebrew/bin/edge-tts"),
      URL(fileURLWithPath: "/usr/local/bin/edge-tts"),
    ]
    return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
  }

  private func neuralAudioCacheURL(token: UUID) -> URL? {
    guard let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else { return nil }
    let directory = cacheRoot.appendingPathComponent("com.harris.ClaudeNarrator", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return directory.appendingPathComponent("reply-\(token.uuidString).mp3")
    } catch {
      return nil
    }
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in
      guard self.activeEngine == .neural, self.audioPlayer === player else { return }
      self.playbackState = .idle
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      guard self.activeEngine == .system else { return }
      self.playbackState = .speaking
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      guard self.activeEngine == .system else { return }
      self.playbackState = .paused
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      guard self.activeEngine == .system else { return }
      self.playbackState = .speaking
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      guard self.activeEngine == .system, !synthesizer.isSpeaking else { return }
      self.playbackState = .idle
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      guard self.activeEngine == .system, !synthesizer.isSpeaking else { return }
      self.playbackState = .idle
    }
  }

  private func preferredSystemVoice() -> AVSpeechSynthesisVoice? {
    let preferredIdentifiers = [
      "com.apple.voice.premium.zh-CN.Tingting",
      "com.apple.voice.enhanced.zh-CN.Tingting",
    ]
    let voices = AVSpeechSynthesisVoice.speechVoices()
    return preferredIdentifiers.lazy.compactMap { identifier in
      voices.first(where: { $0.identifier == identifier })
    }.first ?? AVSpeechSynthesisVoice(language: "zh-CN")
  }

  private enum Keys {
    static let muted = "isMuted"
    static let rate = "speechRatePercent"
    static let useNaturalVoice = "useNaturalVoice"
    static let neuralVoiceID = "neuralVoiceID"
  }
}
