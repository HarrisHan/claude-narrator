import AppKit
import ServiceManagement
import SwiftUI

struct NarratorMenuView: View {
  @ObservedObject var appState: AppState
  @ObservedObject var speech: SpeechController
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
  @State private var launchAtLoginError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header

      if !speech.lastSpokenText.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          Text("最近讲述")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(speech.lastSpokenText)
            .font(.callout)
            .lineLimit(6)
            .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
      }

      HStack(spacing: 8) {
        Button {
          speech.togglePauseResume()
        } label: {
          Label(
            speech.playbackState == .paused ? "继续" : "暂停",
            systemImage: speech.playbackState == .paused ? "play.fill" : "pause.fill"
          )
        }
        .disabled(
          (speech.playbackState != .speaking && speech.playbackState != .paused)
            || speech.isMuted
        )

        Button {
          appState.stopAll()
        } label: {
          Label("停止", systemImage: "stop.fill")
        }
        .disabled(speech.playbackState == .idle && !appState.isSummarizing)

        Button {
          appState.replay()
        } label: {
          Label("重播", systemImage: "arrow.counterclockwise")
        }
        .disabled(speech.lastSpokenText.isEmpty || speech.isMuted)
      }
      .buttonStyle(.bordered)

      Toggle(
        isOn: Binding(
          get: { speech.isMuted },
          set: { speech.setMuted($0) }
        )
      ) {
        Label("静音并停止自动播报", systemImage: "speaker.slash")
      }

      Toggle(isOn: $appState.smartSummaryEnabled) {
        VStack(alignment: .leading, spacing: 2) {
          Text("本机智能口语润色")
          Text("可选；不可用或长回答时按原文播报")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Toggle(isOn: $speech.useNaturalVoice) {
        VStack(alignment: .leading, spacing: 2) {
          Text("自然神经语音")
          Text(speech.naturalVoiceAvailable ? "更接近真人，需要联网" : "组件不可用，将使用系统语音")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .disabled(!speech.naturalVoiceAvailable)

      Picker("音色", selection: $speech.neuralVoiceID) {
        ForEach(SpeechController.neuralVoices) { voice in
          Text(voice.displayName).tag(voice.id)
        }
      }
      .disabled(!speech.useNaturalVoice || !speech.naturalVoiceAvailable)

      Text("当前：\(speech.voiceModeDescription)")
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Label("语速", systemImage: "gauge.with.dots.needle.50percent")
          Spacer()
          Text("\(Int(speech.ratePercent))%")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        Slider(value: $speech.ratePercent, in: 70...150, step: 5)
      }

      Divider()

      Toggle(
        "登录时启动",
        isOn: Binding(
          get: { launchAtLogin },
          set: updateLaunchAtLogin
        ))

      if let launchAtLoginError {
        Text(launchAtLoginError)
          .font(.caption)
          .foregroundStyle(.red)
      }

      VStack(alignment: .leading, spacing: 3) {
        Text("快捷键")
          .font(.caption.weight(.semibold))
        Text("⌃⌥Space 暂停/继续  ·  ⌃⌥M 静音")
        Text("⌃⌥S 停止  ·  ⌃⌥R 重播")
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack {
        Button("复制讲述") { appState.copyLatestSummary() }
          .disabled(speech.lastSpokenText.isEmpty)
        Spacer()
        Button("退出") { NSApp.terminate(nil) }
      }
    }
    .padding(14)
    .frame(width: 340)
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(systemName: appState.menuBarIcon)
        .font(.title2)
        .foregroundStyle(statusColor)
      VStack(alignment: .leading, spacing: 2) {
        Text("Claude Narrator")
          .font(.headline)
        Text(appState.statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text(appState.summaryMode)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }

  private var statusColor: Color {
    if speech.isMuted { return .secondary }
    if case .failed = appState.serverState { return .orange }
    return speech.playbackState == .speaking ? .accentColor : .primary
  }

  private func updateLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLogin = enabled
      launchAtLoginError = nil
    } catch {
      launchAtLogin = SMAppService.mainApp.status == .enabled
      launchAtLoginError = "无法更新登录项：\(error.localizedDescription)"
    }
  }
}
