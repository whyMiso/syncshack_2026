import AppKit
import ApplicationServices
import Foundation

/// Executes `GestureAction`s. All entry points are main-thread;
/// blocking work (CLI subprocesses) runs on a utility queue.
@MainActor
final class ActionExecutor {

    enum Outcome {
        case success(description: String)
        case failure(message: String)
    }

    /// Flips the "run actions" switch and reports the new state.
    ///
    /// Injected by `AppState`, which owns the setting. Keeping it here means
    /// every action still runs through one place, even this one.
    var toggleActionsHandler: (() -> Bool)?

    /// Runs the action and reports what happened for the UI banner.
    func execute(_ action: GestureAction, completion: @escaping (Outcome) -> Void) {
        switch action {
        case .none:
            completion(.success(description: "No action assigned"))

        case .screenshot:
            takeScreenshot(completion: completion)

        case .launchApp(let bundleID, let name):
            launchApp(bundleID: bundleID, name: name, completion: completion)

        case .hideApp(let bundleID, let name):
            hideApp(bundleID: bundleID, name: name, completion: completion)

        case .minimiseWindow:
            minimiseFrontWindow(completion: completion)

        case .media(let command):
            sendMediaCommand(command, completion: completion)

        case .openURL(let urlString):
            openURL(urlString, completion: completion)

        case .runShortcut(let name):
            runShortcut(named: name, completion: completion)

        case .keystroke(let combo):
            sendKeystroke(combo, completion: completion)

        case .macro(let name, let steps):
            runMacro(named: name, steps: steps, completion: completion)

        case .toggleActions:
            guard let toggleActionsHandler else {
                completion(.failure(message: "Nothing is wired up to pause gestures"))
                return
            }
            let running = toggleActionsHandler()
            completion(.success(description: running
                                ? "Gestures resumed"
                                : "Gestures paused — repeat to resume"))
        }
    }

    // MARK: - Macros

    /// How long to pause between chunks of typed text. Posting a long string
    /// in one go, or with no gap, makes some apps drop characters.
    private static let typingChunkDelay: Duration = .milliseconds(10)
    /// UTF-16 units per synthetic event. The unicode buffer is only dependable
    /// for short runs.
    private static let typingChunkSize = 20

    private func runMacro(named name: String, steps: [MacroStep],
                          completion: @escaping (Outcome) -> Void) {
        guard !steps.isEmpty else {
            completion(.failure(message: "Macro “\(name)” has no steps"))
            return
        }

        // Typing and key presses are synthetic events, so the whole macro is
        // gated on Accessibility rather than failing partway through it.
        let needsAccessibility = steps.contains {
            switch $0 {
            case .typeText, .keystroke, .minimiseWindow, .media: return true
            default: return false
            }
        }
        if needsAccessibility, !Self.isAccessibilityTrusted {
            Self.requestAccessibilityPermission()
            completion(.failure(message: "Macros that type need Accessibility permission (System Settings → Privacy & Security → Accessibility)"))
            return
        }

        Task { @MainActor in
            for (index, step) in steps.enumerated() {
                if let failure = await self.perform(step) {
                    completion(.failure(message: "Macro “\(name)” stopped at step \(index + 1): \(failure)"))
                    return
                }
            }
            let label = name.trimmingCharacters(in: .whitespaces)
            completion(.success(description: label.isEmpty
                                ? "Ran macro (\(steps.count) steps)"
                                : "Ran “\(label)”"))
        }
    }

    /// Runs one step. Returns a message on failure, nil on success.
    private func perform(_ step: MacroStep) async -> String? {
        switch step {
        case .typeText(let text):
            guard !text.isEmpty else { return nil }
            await typeText(text)
            return nil

        case .keystroke(let combo):
            return await withCheckedContinuation { continuation in
                sendKeystroke(combo) { outcome in
                    if case .failure(let message) = outcome {
                        continuation.resume(returning: message)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }

        case .delay(let seconds):
            try? await Task.sleep(for: .seconds(max(0, min(seconds, 30))))
            return nil

        case .launchApp(let bundleID, let name):
            return await withCheckedContinuation { continuation in
                launchApp(bundleID: bundleID, name: name) { outcome in
                    if case .failure(let message) = outcome {
                        continuation.resume(returning: message)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }

        case .hideApp(let bundleID, let name):
            return await withCheckedContinuation { continuation in
                hideApp(bundleID: bundleID, name: name) { outcome in
                    if case .failure(let message) = outcome {
                        continuation.resume(returning: message)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }

        case .media(let command):
            return await withCheckedContinuation { continuation in
                sendMediaCommand(command) { outcome in
                    if case .failure(let message) = outcome {
                        continuation.resume(returning: message)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }

        case .minimiseWindow:
            return await withCheckedContinuation { continuation in
                minimiseFrontWindow { outcome in
                    if case .failure(let message) = outcome {
                        continuation.resume(returning: message)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }

        case .openURL(let url):
            return await withCheckedContinuation { continuation in
                openURL(url) { outcome in
                    if case .failure(let message) = outcome {
                        continuation.resume(returning: message)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }

        case .runShortcut(let name):
            return await withCheckedContinuation { continuation in
                runShortcut(named: name) { outcome in
                    if case .failure(let message) = outcome {
                        continuation.resume(returning: message)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    /// Types a string into whatever app is frontmost.
    ///
    /// Uses `keyboardSetUnicodeString` rather than mapping characters to
    /// virtual key codes, so any text works — punctuation, accents, emoji —
    /// regardless of the user's keyboard layout.
    private func typeText(_ text: String) async {
        let source = CGEventSource(stateID: .hidSystemState)
        for chunk in text.chunked(into: Self.typingChunkSize) {
            var utf16 = Array(chunk.utf16)
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source,
                                          virtualKey: 0, keyDown: isDown) else { continue }
                event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                event.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(for: Self.typingChunkDelay)
        }
    }

    // MARK: - Screenshot

    /// True if the app may capture the screen. Checks without prompting.
    static var isScreenRecordingAuthorized: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// The system prompt is raised at most once per launch. `screencapture`
    /// raises a fresh dialog on every denied attempt, so without this a
    /// repeated gesture turns into a stream of identical prompts.
    private static var hasRequestedScreenRecording = false

    static func requestScreenRecordingPermission() {
        hasRequestedScreenRecording = true
        CGRequestScreenCaptureAccess()
    }

    private func takeScreenshot(completion: @escaping (Outcome) -> Void) {
        guard Self.isScreenRecordingAuthorized else {
            if !Self.hasRequestedScreenRecording {
                Self.requestScreenRecordingPermission()
            }
            completion(.failure(message: "Screenshot needs Screen Recording permission — grant it in System Settings → Privacy & Security → Screen Recording, then quit and reopen SayHi"))
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        let path = desktop
            .appendingPathComponent("SayHi Screenshot \(formatter.string(from: Date())).png").path

        runProcess("/usr/sbin/screencapture", arguments: ["-x", path]) { status, _ in
            if status == 0 {
                completion(.success(description: "Screenshot saved to Desktop"))
            } else {
                completion(.failure(message: "Screenshot failed (screencapture exited \(status))"))
            }
        }
    }

    // MARK: - Launch application

    private func launchApp(bundleID: String, name: String, completion: @escaping (Outcome) -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            completion(.failure(message: "\(name) is not installed"))
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(message: "Couldn't open \(name): \(error.localizedDescription)"))
                } else {
                    completion(.success(description: "Opened \(name)"))
                }
            }
        }
    }

    // MARK: - Hide / minimise

    /// Hides every window of an app. Uses `NSRunningApplication`, so unlike a
    /// true minimise-to-Dock it needs no Accessibility permission.
    private func hideApp(bundleID: String, name: String,
                         completion: @escaping (Outcome) -> Void) {
        let target: NSRunningApplication?
        if bundleID.isEmpty {
            target = NSWorkspace.shared.frontmostApplication
        } else {
            target = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID).first
        }
        guard let target else {
            completion(.failure(message: bundleID.isEmpty
                                ? "No frontmost application to hide"
                                : "\(name) isn't running"))
            return
        }
        let label = target.localizedName ?? (name.isEmpty ? "application" : name)
        let pid = target.processIdentifier

        if target == .current {
            // An app cannot hide itself through NSRunningApplication.
            NSApp.hide(nil)
            completion(.success(description: "Hid \(label)"))
            return
        }

        target.hide()

        // `hide()` is asynchronous and returns false even when it works, so the
        // outcome is confirmed by re-reading the app's state rather than trusted.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            let hidden = NSRunningApplication(processIdentifier: pid)?.isHidden ?? false
            completion(hidden
                       ? .success(description: "Hid \(label)")
                       : .failure(message: "Couldn't hide \(label)"))
        }
    }

    /// Minimises the frontmost window to the Dock via the Accessibility API,
    /// which is the only way to drive another app's window controls.
    private func minimiseFrontWindow(completion: @escaping (Outcome) -> Void) {
        guard Self.isAccessibilityTrusted else {
            Self.requestAccessibilityPermission()
            completion(.failure(message: "Minimising needs Accessibility permission (System Settings → Privacy & Security → Accessibility). “Hide Application” works without it."))
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication else {
            completion(.failure(message: "No frontmost application"))
            return
        }

        let axApp = AXUIElementCreateApplication(front.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp,
                                            kAXFocusedWindowAttribute as CFString,
                                            &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            completion(.failure(message: "\(front.localizedName ?? "That app") has no window to minimise"))
            return
        }

        let window = raw as! AXUIElement
        let status = AXUIElementSetAttributeValue(window,
                                                  kAXMinimizedAttribute as CFString,
                                                  kCFBooleanTrue)
        if status == .success {
            completion(.success(description: "Minimised \(front.localizedName ?? "window")"))
        } else {
            completion(.failure(message: "That window can't be minimised"))
        }
    }

    // MARK: - Media keys

    /// Posts the media key for a command.
    ///
    /// Media keys are delivered as `NSSystemDefined` events rather than normal
    /// key presses, which is why this can't reuse `sendKeystroke`. The system
    /// routes them to whichever app is currently playing, so Spotify responds
    /// without being frontmost.
    private func sendMediaCommand(_ command: MediaCommand,
                                  completion: @escaping (Outcome) -> Void) {
        guard Self.isAccessibilityTrusted else {
            Self.requestAccessibilityPermission()
            completion(.failure(message: "Media controls need Accessibility permission (System Settings → Privacy & Security → Accessibility)"))
            return
        }

        for isDown in [true, false] {
            // The HID system packs the key type and up/down state into data1,
            // and mirrors the state in the modifier flags.
            let state: Int32 = isDown ? 0xA : 0xB
            let data1 = Int((command.keyType << 16) | (state << 8))
            guard let event = NSEvent.otherEvent(with: .systemDefined,
                                                 location: .zero,
                                                 modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
                                                 timestamp: 0,
                                                 windowNumber: 0,
                                                 context: nil,
                                                 subtype: 8,
                                                 data1: data1,
                                                 data2: -1),
                  let cgEvent = event.cgEvent else {
                completion(.failure(message: "Couldn't create the media key event"))
                return
            }
            cgEvent.post(tap: .cghidEventTap)
        }
        completion(.success(description: command.displayName))
    }

    // MARK: - Open URL

    private func openURL(_ urlString: String, completion: @escaping (Outcome) -> Void) {
        guard let url = URL(string: urlString), url.scheme != nil else {
            completion(.failure(message: "Invalid URL: \(urlString)"))
            return
        }
        NSWorkspace.shared.open(url)
        completion(.success(description: "Opened \(url.host ?? urlString)"))
    }

    // MARK: - Shortcuts

    private func runShortcut(named name: String, completion: @escaping (Outcome) -> Void) {
        runProcess("/usr/bin/shortcuts", arguments: ["run", name]) { status, stderr in
            if status == 0 {
                completion(.success(description: "Ran Shortcut “\(name)”"))
            } else {
                let detail = stderr.isEmpty ? "is it spelled exactly as in the Shortcuts app?" : stderr
                completion(.failure(message: "Shortcut “\(name)” failed — \(detail)"))
            }
        }
    }

    /// Names of the user's Shortcuts, for the mapping editor's picker.
    /// Calls back on the main thread; empty array if the CLI is unavailable.
    nonisolated static func availableShortcuts(_ completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            var names: [String] = []
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                names = String(decoding: data, as: UTF8.self)
                    .split(separator: "\n").map(String.init)
            } catch {}
            DispatchQueue.main.async { completion(names) }
        }
    }

    // MARK: - Keystrokes

    /// True if the app may post synthetic keyboard events.
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt directing the user to System Settings →
    /// Privacy & Security → Accessibility.
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func sendKeystroke(_ combo: KeyCombo, completion: @escaping (Outcome) -> Void) {
        guard Self.isAccessibilityTrusted else {
            Self.requestAccessibilityPermission()
            completion(.failure(message: "Keyboard shortcuts need Accessibility permission (System Settings → Privacy & Security → Accessibility)"))
            return
        }
        guard let keyCode = combo.keyCode else {
            completion(.failure(message: "Unknown key “\(combo.keyName)”"))
            return
        }

        var flags = CGEventFlags()
        if combo.command { flags.insert(.maskCommand) }
        if combo.shift   { flags.insert(.maskShift) }
        if combo.option  { flags.insert(.maskAlternate) }
        if combo.control { flags.insert(.maskControl) }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            completion(.failure(message: "Couldn't create keyboard event"))
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        completion(.success(description: "Pressed \(combo.displayString)"))
    }

    // MARK: - Subprocess helper

    /// Runs a CLI tool off the main thread; calls back on main with exit status.
    private func runProcess(_ path: String, arguments: [String],
                            completion: @escaping (Int32, String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = Pipe()
            var status: Int32 = -1
            var stderr = ""
            do {
                try process.run()
                process.waitUntilExit()
                status = process.terminationStatus
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                stderr = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                stderr = error.localizedDescription
            }
            DispatchQueue.main.async { completion(status, stderr) }
        }
    }
}

private extension String {
    /// Splits into runs of at most `size` characters, preserving order.
    func chunked(into size: Int) -> [String] {
        guard size > 0, !isEmpty else { return [] }
        var chunks: [String] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[start..<end]))
            start = end
        }
        return chunks
    }
}
