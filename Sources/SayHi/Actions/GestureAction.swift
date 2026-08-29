import AppKit
import Carbon.HIToolbox
import Foundation

/// A keyboard combination, stored by macOS virtual key code.
struct KeyCombo: Codable, Equatable, Hashable {
    var keyName: String  // human-readable key from `KeyCombo.keyCodes`
    var command = false
    var shift = false
    var option = false
    var control = false
    /// The physical Fn / Globe key. Not part of Carbon hotkeys (unsupported),
    /// but replayed for the keystroke action via CGEvent's secondary-fn flag.
    var fn = false

    /// The exact virtual key code captured by the recorder, when the combo was
    /// set by pressing keys rather than chosen from the old list. Optional so
    /// combos saved before the recorder existed still decode (they fall back to
    /// looking the code up from `keyName`).
    var recordedKeyCode: UInt16? = nil

    var keyCode: UInt16? { recordedKeyCode ?? KeyCombo.keyCodes[keyName] }

    private enum CodingKeys: String, CodingKey {
        case keyName, command, shift, option, control, fn, recordedKeyCode
    }

    init(keyName: String, command: Bool = false, shift: Bool = false,
         option: Bool = false, control: Bool = false, fn: Bool = false,
         recordedKeyCode: UInt16? = nil) {
        self.keyName = keyName; self.command = command; self.shift = shift
        self.option = option; self.control = control; self.fn = fn
        self.recordedKeyCode = recordedKeyCode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyName = (try? c.decode(String.self, forKey: .keyName)) ?? ""
        command = (try? c.decode(Bool.self, forKey: .command)) ?? false
        shift   = (try? c.decode(Bool.self, forKey: .shift)) ?? false
        option  = (try? c.decode(Bool.self, forKey: .option)) ?? false
        control = (try? c.decode(Bool.self, forKey: .control)) ?? false
        fn      = (try? c.decode(Bool.self, forKey: .fn)) ?? false
        recordedKeyCode = try? c.decode(UInt16.self, forKey: .recordedKeyCode)
    }

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
        if fn      { parts.append("🌐") }
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
        "F13": 105, "F14": 107, "F15": 113, "F16": 106, "F17": 64,
        "F18": 79, "F19": 80, "F20": 90,
        "Home": 115, "End": 119, "Page Up": 116, "Page Down": 121,
        "Fwd Delete": 117, "Help": 114, "Enter": 76,
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

    /// keyCode → display name, inverted from `keyCodes`, for the recorder.
    private static let namesByCode: [UInt16: String] = {
        var m: [UInt16: String] = [:]
        for (name, code) in keyCodes { m[code] = name }
        return m
    }()

    /// Builds a combo from a captured key-down event. Returns nil for a bare
    /// modifier press or a key that produces no usable label.
    static func from(event: NSEvent) -> KeyCombo? {
        guard event.type == .keyDown else { return nil }
        let f = event.modifierFlags
        guard let name = label(forKeyCode: event.keyCode,
                               characters: event.charactersIgnoringModifiers) else { return nil }
        // .function is auto-set on arrows, F-keys and nav keys, so it only
        // signals a real Fn press on an otherwise-ordinary key.
        let fnHeld = f.contains(.function) && !intrinsicFunctionKeys.contains(event.keyCode)
        return KeyCombo(keyName: name,
                        command: f.contains(.command),
                        shift: f.contains(.shift),
                        option: f.contains(.option),
                        control: f.contains(.control),
                        fn: fnHeld,
                        recordedKeyCode: event.keyCode)
    }

    /// Key codes that macOS flags as "function" regardless of the Fn key:
    /// arrows, F1–F20, and the navigation cluster.
    private static let intrinsicFunctionKeys: Set<UInt16> = [
        123, 124, 125, 126,                                   // arrows
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1–F12
        105, 107, 113, 106, 64, 79, 80, 90,                   // F13–F20
        115, 119, 116, 121, 117, 114, 71,                     // home/end/pgup/pgdn/fdel/help/clear
    ]

    /// A human label for a key code: the curated name if known, otherwise the
    /// printable character the key produces (symbols like `-` `[` `;`).
    private static func label(forKeyCode code: UInt16, characters: String?) -> String? {
        if let name = namesByCode[code] { return name }
        if let ch = characters?.first, !ch.isWhitespace, !ch.isNewline,
           ch.unicodeScalars.allSatisfy({ !$0.properties.isDefaultIgnorableCodePoint && $0.value >= 0x20 }) {
            return String(ch).uppercased()
        }
        return nil
    }
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

/// A macOS window-tiling arrangement, triggered by pressing the frontmost app's
/// Window ▸ Move & Resize menu item. Driving the menu (rather than replaying the
/// Fn+arrow shortcut) sidesteps macOS remapping Fn+← to Home before any app sees
/// it — the very thing that makes those shortcuts impossible to record.
enum TileArrangement: String, Codable, CaseIterable, Identifiable, Hashable {
    case left, right, leftAndRight, top, bottom, fill, center, restore

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left:         return "Left Half"
        case .right:        return "Right Half"
        case .leftAndRight: return "Left & Right Split"
        case .top:          return "Top Half"
        case .bottom:       return "Bottom Half"
        case .fill:         return "Fill Screen"
        case .center:       return "Centre"
        case .restore:      return "Restore Size"
        }
    }

    var symbol: String {
        switch self {
        case .left:         return "rectangle.lefthalf.filled"
        case .right:        return "rectangle.righthalf.filled"
        case .leftAndRight: return "rectangle.split.2x1"
        case .top:          return "rectangle.tophalf.filled"
        case .bottom:       return "rectangle.bottomhalf.filled"
        case .fill:         return "rectangle.fill"
        case .center:       return "rectangle.center.inset.filled"
        case .restore:      return "arrow.uturn.backward"
        }
    }

    /// Titles to walk from the app's "Window" menu down to the item to press.
    var menuPath: [String] {
        switch self {
        case .left:         return ["Move & Resize", "Left"]
        case .right:        return ["Move & Resize", "Right"]
        case .leftAndRight: return ["Move & Resize", "Left & Right"]
        case .top:          return ["Move & Resize", "Top"]
        case .bottom:       return ["Move & Resize", "Bottom"]
        case .fill:         return ["Fill"]
        case .center:       return ["Center"]
        case .restore:      return ["Move & Resize", "Return to Previous Size"]
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
    case tileWindow(TileArrangement)
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
        case .tileWindow(let a):        return "Tile: \(a.displayName)"
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
        case tileWindow = "Tile window"
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
        case .tileWindow: return .tileWindow
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
        case .tileWindow:  return .tileWindow(.leftAndRight)
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
    /// Snap the frontmost window using macOS window tiling.
    case tileWindow(TileArrangement)

    var displayName: String {
        switch self {
        case .none:                     return "Unassigned"
        case .screenshot:               return "Screenshot"
        case .launchApp(_, let name):   return "Open \(name)"
        case .hideApp(let id, let name):
            return id.isEmpty ? "Hide front app" : "Hide \(name)"
        case .minimiseWindow:           return "Minimise window"
        case .media(let command):       return command.displayName
        case .tileWindow(let a):        return "Tile: \(a.displayName)"
        case .openURL(let url):         return "Open \(url)"
        case .runShortcut(let name):    return "Run Shortcut: “\(name)”"
        case .keystroke(let combo):     return "Press \(combo.displayString)"
        case .macro(let name, let steps):
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "Macro (\(steps.count) steps)" : trimmed
        case .toggleActions:            return "Pause / Resume Gestures"
        case .tileWindow(let a):        return "Tile: \(a.displayName)"
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
        case tileWindow = "Tile Window"
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
        case .tileWindow: return .tileWindow
        }
    }
}
