import Carbon.HIToolbox
import Foundation

/// A keyboard combination, stored by macOS virtual key code.
struct KeyCombo: Codable, Equatable, Hashable {
    var keyName: String  // human-readable key from `KeyCombo.keyCodes`
    var command = false
    var shift = false
    var option = false
    var control = false

    var keyCode: UInt16? { KeyCombo.keyCodes[keyName] }

    /// Modifier mask in Carbon's encoding, for `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if command { mask |= UInt32(cmdKey) }
        if shift   { mask |= UInt32(shiftKey) }
        if option  { mask |= UInt32(optionKey) }
        if control { mask |= UInt32(controlKey) }
        return mask
    }

    var hasModifier: Bool { command || shift || option || control }

    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option  { parts.append("⌥") }
        if shift   { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(keyName)
        return parts.joined()
    }

    /// Curated map of key names to macOS virtual key codes (kVK_* constants).
    static let keyCodes: [String: UInt16] = [
        "A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5, "H": 4,
        "I": 34, "J": 38, "K": 40, "L": 37, "M": 46, "N": 45, "O": 31,
        "P": 35, "Q": 12, "R": 15, "S": 1, "T": 17, "U": 32, "V": 9,
        "W": 13, "X": 7, "Y": 16, "Z": 6,
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22,
        "7": 26, "8": 28, "9": 25,
        "Space": 49, "Return": 36, "Tab": 48, "Escape": 53, "Delete": 51,
        "←": 123, "→": 124, "↓": 125, "↑": 126,
        "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96, "F6": 97,
        "F7": 98, "F8": 100, "F9": 101, "F10": 109, "F11": 103, "F12": 111,
    ]

    /// Key names in a stable, picker-friendly order.
    static let orderedKeyNames: [String] = {
        let letters = (UnicodeScalar("A").value...UnicodeScalar("Z").value)
            .compactMap { UnicodeScalar($0).map(String.init) }
        let digits = (0...9).map(String.init)
        let special = ["Space", "Return", "Tab", "Escape", "Delete", "←", "→", "↓", "↑"]
        let fKeys = (1...12).map { "F\($0)" }
        return letters + digits + special + fKeys
    }()
}

/// A system media command, delivered as the corresponding media key.
///
/// These are system-wide, so they reach whichever app is currently playing —
/// Spotify, Music, video in a browser — without it having to be frontmost.
enum MediaCommand: String, Codable, CaseIterable, Identifiable, Hashable {
    case playPause
    case next
    case previous
    case volumeUp
    case volumeDown
    case mute

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .playPause:  return "Play / Pause"
        case .next:       return "Next Track"
        case .previous:   return "Previous Track"
        case .volumeUp:   return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute:       return "Mute"
        }
    }

    var symbol: String {
        switch self {
        case .playPause:  return "playpause.fill"
        case .next:       return "forward.end.fill"
        case .previous:   return "backward.end.fill"
        case .volumeUp:   return "speaker.wave.3.fill"
        case .volumeDown: return "speaker.wave.1.fill"
        case .mute:       return "speaker.slash.fill"
        }
    }

    /// `NX_KEYTYPE_*` constant from IOKit's HID system.
    var keyType: Int32 {
        switch self {
        case .volumeUp:   return 0   // NX_KEYTYPE_SOUND_UP
        case .volumeDown: return 1   // NX_KEYTYPE_SOUND_DOWN
        case .mute:       return 7   // NX_KEYTYPE_MUTE
        case .playPause:  return 16  // NX_KEYTYPE_PLAY
        case .next:       return 19  // NX_KEYTYPE_FAST
        case .previous:   return 20  // NX_KEYTYPE_REWIND
        }
    }
}

/// One step in a macro. Steps run in order, each waiting for the previous.
///
/// Kept separate from `GestureAction` rather than reusing it: a macro step is
/// a building block with no meaning on its own, and nesting actions inside
/// actions would allow a macro to contain itself.
enum MacroStep: Codable, Equatable, Hashable, Identifiable {
    case typeText(String)
    case keystroke(KeyCombo)
    case delay(TimeInterval)
    case launchApp(bundleID: String, name: String)
    /// An empty bundle id means "whatever is frontmost when this runs".
    case hideApp(bundleID: String, name: String)
    case minimiseWindow
    case media(MediaCommand)
    case openURL(String)
    case runShortcut(name: String)

    var id: String { summary }

    var summary: String {
        switch self {
        case .typeText(let text):
            let oneLine = text.replacingOccurrences(of: "\n", with: "⏎")
            let clipped = oneLine.count > 40 ? String(oneLine.prefix(40)) + "…" : oneLine
            return "Type “\(clipped)”"
        case .keystroke(let combo):     return "Press \(combo.displayString)"
        case .delay(let seconds):       return String(format: "Wait %.2gs", seconds)
        case .launchApp(_, let name):   return "Open \(name)"
        case .hideApp(let id, let name):
            return id.isEmpty ? "Hide the front app" : "Hide \(name)"
        case .minimiseWindow:           return "Minimise the front window"
        case .media(let command):       return command.displayName
        case .openURL(let url):         return "Open \(url)"
        case .runShortcut(let name):    return "Run Shortcut “\(name)”"
        }
    }

    enum Kind: String, CaseIterable, Identifiable {
        case typeText = "Type text"
        case keystroke = "Press keys"
        case delay = "Wait"
        case launchApp = "Open application"
        case hideApp = "Hide application"
        case minimiseWindow = "Minimise window"
        case media = "Media control"
        case openURL = "Open URL"
        case runShortcut = "Run Shortcut"
        var id: String { rawValue }
    }

    var kind: Kind {
        switch self {
        case .typeText: return .typeText
        case .keystroke: return .keystroke
        case .delay: return .delay
        case .launchApp: return .launchApp
        case .hideApp: return .hideApp
        case .minimiseWindow: return .minimiseWindow
        case .media: return .media
        case .openURL: return .openURL
        case .runShortcut: return .runShortcut
        }
    }

    /// A blank step of the given kind, for the "add step" menu.
    static func empty(_ kind: Kind) -> MacroStep {
        switch kind {
        case .typeText:    return .typeText("")
        case .keystroke:   return .keystroke(KeyCombo(keyName: "Return"))
        case .delay:       return .delay(0.5)
        case .launchApp:   return .launchApp(bundleID: "", name: "")
        case .hideApp:     return .hideApp(bundleID: "", name: "")
        case .minimiseWindow: return .minimiseWindow
        case .media:       return .media(.playPause)
        case .openURL:     return .openURL("https://")
        case .runShortcut: return .runShortcut(name: "")
        }
    }
}

/// An action a gesture can trigger. Codable so mappings persist as JSON.
/// To add a new action type later (AppleScript, shell command, media keys…)
/// add a case here, a branch in `ActionExecutor`, and a config UI section.
enum GestureAction: Codable, Equatable, Hashable {
    case none
    case screenshot
    case launchApp(bundleID: String, name: String)
    /// Hides an app's windows. An empty bundle id means the frontmost app.
    case hideApp(bundleID: String, name: String)
    /// Minimises the frontmost window to the Dock.
    case minimiseWindow
    /// Play/pause, skip, volume — reaches whatever is playing.
    case media(MediaCommand)
    case openURL(String)
    case runShortcut(name: String)
    case keystroke(KeyCombo)
    /// An ordered sequence — type an email, wait, press Return.
    case macro(name: String, steps: [MacroStep])
    /// Pauses and resumes every *other* gesture, so hands can be used freely.
    /// Deliberately still fires while paused — that is the whole point of it.
    case toggleActions
    /// Stops the camera and recognition outright — the same switch as
    /// "Gesture Control: OFF" in the toolbar.
    ///
    /// One-way by nature, not by oversight: with the camera stopped nothing
    /// can see your hands, so no gesture can undo it. The way back is the menu
    /// bar or the toolbar, and the confirmation banner says so.
    case stopCamera

    var displayName: String {
        switch self {
        case .none:                     return "Unassigned"
        case .screenshot:               return "Screenshot"
        case .launchApp(_, let name):   return "Open \(name)"
        case .hideApp(let id, let name):
            return id.isEmpty ? "Hide front app" : "Hide \(name)"
        case .minimiseWindow:           return "Minimise window"
        case .media(let command):       return command.displayName
        case .openURL(let url):         return "Open \(url)"
        case .runShortcut(let name):    return "Run Shortcut: “\(name)”"
        case .keystroke(let combo):     return "Press \(combo.displayString)"
        case .macro(let name, let steps):
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "Macro (\(steps.count) steps)" : trimmed
        case .toggleActions:            return "Pause / Resume Gestures"
        case .stopCamera:               return "Turn Camera Off"
        }
    }

    /// Coarse type, used by the mapping editor's type picker.
    enum Kind: String, CaseIterable, Identifiable {
        case none = "None"
        case screenshot = "Screenshot"
        case launchApp = "Launch Application"
        case hideApp = "Hide Application"
        case minimiseWindow = "Minimise Window"
        case media = "Media Control"
        case openURL = "Open URL"
        case runShortcut = "Run macOS Shortcut"
        case keystroke = "Keyboard Shortcut"
        case macro = "Macro (multiple steps)"
        case toggleActions = "Pause / Resume Gestures"
        case stopCamera = "Turn Camera Off"
        var id: String { rawValue }
    }

    var kind: Kind {
        switch self {
        case .none: return .none
        case .screenshot: return .screenshot
        case .launchApp: return .launchApp
        case .hideApp: return .hideApp
        case .minimiseWindow: return .minimiseWindow
        case .media: return .media
        case .openURL: return .openURL
        case .runShortcut: return .runShortcut
        case .keystroke: return .keystroke
        case .macro: return .macro
        case .toggleActions: return .toggleActions
        case .stopCamera: return .stopCamera
        }
    }
}
