import AppKit
import SwiftUI

@main
struct ClaudeNarratorApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var appState = AppState()

  var body: some Scene {
    Window("Claude Narrator", id: "control") {
      NarratorMenuView(appState: appState, speech: appState.speech)
    }
    .defaultSize(width: 380, height: 620)
    .windowResizability(.contentSize)

    MenuBarExtra {
      NarratorMenuView(appState: appState, speech: appState.speech)
    } label: {
      NarratorMenuLabel(appState: appState, speech: appState.speech)
    }
    .menuBarExtraStyle(.window)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      sender.windows.first(where: \.canBecomeMain)?.makeKeyAndOrderFront(nil)
    }
    return true
  }
}

private struct NarratorMenuLabel: View {
  @ObservedObject var appState: AppState
  @ObservedObject var speech: SpeechController

  var body: some View {
    Image(systemName: appState.menuBarIcon)
      .accessibilityLabel(appState.statusText)
  }
}
