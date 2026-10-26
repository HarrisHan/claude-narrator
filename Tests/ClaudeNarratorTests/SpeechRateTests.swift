import AVFAudio
import XCTest

@testable import ClaudeNarrator

final class SpeechRateTests: XCTestCase {
  @MainActor
  func testLiveRateAndPausedResumeUseCurrentSliderValue() throws {
    let controller = SpeechController()
    let savedRate = controller.ratePercent
    let savedMute = controller.isMuted
    let url = try silentAudio()
    defer {
      controller.stop()
      controller.ratePercent = savedRate
      controller.isMuted = savedMute
      try? FileManager.default.removeItem(at: url)
    }
    controller.isMuted = false
    controller.ratePercent = 70
    controller.playNeuralAudio(at: url, fallbackText: "")
    let player = try XCTUnwrap(controller.audioPlayer)
    XCTAssertTrue(player.enableRate)
    XCTAssertEqual(player.rate, 0.7, accuracy: 0.01)

    let position = player.currentTime
    controller.ratePercent = 150
    XCTAssertTrue(controller.audioPlayer === player, "Changing speed must not restart audio")
    XCTAssertEqual(player.rate, 1.5, accuracy: 0.01)
    XCTAssertGreaterThanOrEqual(player.currentTime, position)

    controller.togglePauseResume()
    XCTAssertEqual(controller.playbackState, .paused)
    controller.ratePercent = 85
    XCTAssertEqual(player.rate, 0.85, accuracy: 0.01)
    controller.togglePauseResume()
    XCTAssertEqual(controller.playbackState, .speaking)
    XCTAssertEqual(player.rate, 0.85, accuracy: 0.01)

    // Opening the same cached audio again must use the latest rate.
    controller.stop()
    controller.ratePercent = 125
    controller.playNeuralAudio(at: url, fallbackText: "")
    XCTAssertEqual(try XCTUnwrap(controller.audioPlayer).rate, 1.25, accuracy: 0.01)
  }

  private func silentAudio() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rate-test-\(UUID()).wav")
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 220500))
    buffer.frameLength = buffer.frameCapacity
    buffer.floatChannelData![0].update(repeating: 0, count: Int(buffer.frameLength))
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
  }
}
