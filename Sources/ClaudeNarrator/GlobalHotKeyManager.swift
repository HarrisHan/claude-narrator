import Carbon.HIToolbox
import Foundation

final class GlobalHotKeyManager {
  private let signature: OSType = 0x434C_4E52  // CLNR
  private var eventHandler: EventHandlerRef?
  private var hotKeyRefs: [EventHotKeyRef?] = []
  private var actions: [UInt32: () -> Void] = [:]

  init() {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData -> OSStatus in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == manager.signature else {
          return OSStatus(eventNotHandledErr)
        }
        manager.perform(id: hotKeyID.id)
        return noErr
      },
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )
  }

  func registerDefaults(
    togglePlayback: @escaping () -> Void,
    toggleMute: @escaping () -> Void,
    stop: @escaping () -> Void,
    replay: @escaping () -> Void
  ) {
    register(id: 1, keyCode: UInt32(kVK_Space), action: togglePlayback)
    register(id: 2, keyCode: UInt32(kVK_ANSI_M), action: toggleMute)
    register(id: 3, keyCode: UInt32(kVK_ANSI_S), action: stop)
    register(id: 4, keyCode: UInt32(kVK_ANSI_R), action: replay)
  }

  private func register(id: UInt32, keyCode: UInt32, action: @escaping () -> Void) {
    let hotKeyID = EventHotKeyID(signature: signature, id: id)
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
      keyCode,
      UInt32(controlKey | optionKey),
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &reference
    )
    if status == noErr {
      actions[id] = action
      hotKeyRefs.append(reference)
    }
  }

  private func perform(id: UInt32) {
    guard let action = actions[id] else { return }
    DispatchQueue.main.async(execute: action)
  }

  deinit {
    for reference in hotKeyRefs {
      if let reference { UnregisterEventHotKey(reference) }
    }
    if let eventHandler { RemoveEventHandler(eventHandler) }
  }
}
