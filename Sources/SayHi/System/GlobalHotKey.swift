import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut.
///
/// Uses Carbon's `RegisterEventHotKey` rather than an `NSEvent` global monitor
/// on purpose: global monitors require Accessibility permission, while Carbon
/// hotkeys require none at all — the system delivers the event straight to the
/// app. This app already asks for enough permissions.
///
/// Registration fails if another app already owns the combination, which the
/// caller is expected to surface rather than swallow.
final class GlobalHotKey {

    /// Callbacks keyed by hotkey id. Only touched on the main thread.
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?

    /// Returns nil if the combination is unavailable (already taken, or the
    /// key isn't one the system can register).
    init?(keyCode: UInt16, carbonModifiers: UInt32, action: @escaping () -> Void) {
        // A hotkey with no modifiers would swallow a plain keystroke globally.
        guard carbonModifiers != 0 else { return nil }

        Self.installHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1

        var ref: EventHotKeyRef?
        // Four-char signature identifying this app's hotkeys ('SYHI').
        let hotKeyID = EventHotKeyID(signature: 0x5359_4849, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }

        hotKeyRef = ref
        Self.handlers[id] = action
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        Self.handlers[id] = nil
    }

    /// One process-wide Carbon handler dispatches to the right callback.
    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &pressed)
            guard status == noErr else { return status }
            let id = pressed.id
            DispatchQueue.main.async { GlobalHotKey.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
