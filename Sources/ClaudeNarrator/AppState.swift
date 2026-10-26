import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
  static let hookPort: UInt16 = 17_832

  @Published private(set) var serverState: HookServer.State = .starting
  @Published private(set) var isSummarizing = false
  @Published private(set) var summaryMode = "等待 Claude Code"
  @Published var smartSummaryEnabled: Bool {
    didSet { UserDefaults.standard.set(smartSummaryEnabled, forKey: Keys.smartSummary) }
  }

  let speech = SpeechController()

  private var server: HookServer?
  private var hotKeys: GlobalHotKeyManager?
  private var summaryTask: Task<Void, Never>?
  private var lastReceivedMessage = ""
  private var hasStarted = false

  init() {
    if UserDefaults.standard.object(forKey: Keys.smartSummary) == nil {
      smartSummaryEnabled = false
    } else {
      smartSummaryEnabled = UserDefaults.standard.bool(forKey: Keys.smartSummary)
    }
    start()
  }

  var menuBarIcon: String {
    if speech.isMuted { return "speaker.slash.fill" }
    if isSummarizing { return "text.bubble.fill" }
    switch speech.playbackState {
    case .synthesizing: return "ellipsis.circle.fill"
    case .speaking: return "waveform.circle.fill"
    case .paused: return "pause.circle.fill"
    case .idle:
      return serverState.isReady ? "waveform.circle" : "exclamationmark.triangle.fill"
    }
  }

  var statusText: String {
    if speech.isMuted { return "已静音" }
    if isSummarizing { return "正在整理自然讲述…" }
    switch speech.playbackState {
    case .synthesizing: return "正在生成自然语音…"
    case .speaking: return "正在讲述"
    case .paused: return "已暂停"
    case .idle:
      switch serverState {
      case .ready: return "等待 Claude Code"
      case .starting: return "正在启动接收服务…"
      case .failed(let reason): return "接收服务异常：\(reason)"
      }
    }
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true

    let server = HookServer(port: Self.hookPort)
    server.onStateChange = { [weak self] state in
      Task { @MainActor in self?.serverState = state }
    }
    server.onPayload = { [weak self] payload in
      Task { @MainActor in self?.receive(payload) }
    }
    self.server = server
    server.start()

    let hotKeys = GlobalHotKeyManager()
    hotKeys.registerDefaults(
      togglePlayback: { [weak self] in self?.speech.togglePauseResume() },
      toggleMute: { [weak self] in self?.speech.toggleMute() },
      stop: { [weak self] in self?.stopAll() },
      replay: { [weak self] in self?.speech.replay() }
    )
    self.hotKeys = hotKeys
  }

  func receive(_ payload: HookPayload) {
    guard payload.hookEventName == nil || payload.hookEventName == "Stop" else { return }
    guard
      let message = payload.lastAssistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
      !message.isEmpty,
      message != lastReceivedMessage
    else { return }

    lastReceivedMessage = message
    summaryTask?.cancel()
    isSummarizing = false
    speech.stop()
    speech.prepare(original: message, projectPath: payload.cwd)

    guard !speech.isMuted else {
      let fallback = SpeechTextProcessor.narration(message)
      speech.store(spokenText: fallback)
      summaryMode = "已静音，结果已保存"
      return
    }

    isSummarizing = true
    summaryMode = smartSummaryEnabled ? "正在润色口语表达" : "原文自然播报"
    let useSmartSummary = smartSummaryEnabled

    summaryTask = Task { [weak self] in
      let result = await SpokenSummarizer.summarize(message, preferModel: useSmartSummary)
      guard !Task.isCancelled, let self else { return }
      self.isSummarizing = false
      self.summaryMode = result.mode.displayName
      self.speech.speak(result.text)
    }
  }

  func replay() {
    speech.replay()
  }

  func stopAll() {
    summaryTask?.cancel()
    summaryTask = nil
    isSummarizing = false
    summaryMode = "已停止"
    speech.stop()
  }

  func copyLatestSummary() {
    guard !speech.lastSpokenText.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(speech.lastSpokenText, forType: .string)
  }

  private enum Keys {
    static let smartSummary = "conversationalRewriteEnabled"
  }
}

extension HookServer.State {
  fileprivate var isReady: Bool {
    if case .ready = self { return true }
    return false
  }
}
