import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Gesture → action table, with a column per hand so each gesture can drive
/// two different actions.
struct MappingsView: View {
    @EnvironmentObject private var mappingStore: GestureMappingStore
    @State private var editingBinding: GestureBinding?

    private let gestureColumnWidth: CGFloat = 165

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Gesture.assignable) { gesture in
                        row(for: gesture)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Hairline()
            Text("Hand recognition runs entirely on this Mac. Camera images are not stored or transmitted.")
                .textRole(.body, tint: Palette.inkFaint)
                .padding(.vertical, 10)
        }
        .sheet(item: $editingBinding) { binding in
            ActionEditorView(binding: binding,
                             initialAction: mappingStore.action(for: binding)) { newAction in
                mappingStore.setAction(newAction, for: binding)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            FieldLabel("Gesture")
                .frame(width: gestureColumnWidth, alignment: .leading)
            ForEach(HandSide.allCases) { hand in
                FieldLabel(hand.displayName)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 34)
        .background(Palette.fillInset)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func row(for gesture: Gesture) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                GestureGlyph(gesture: gesture, size: 20)
                Text(gesture.displayName)
                    .textRole(.bodyEmphasis)
                    .lineLimit(1)
            }
            .frame(width: gestureColumnWidth, alignment: .leading)

            ForEach(HandSide.allCases) { hand in
                actionCell(GestureBinding(gesture: gesture, hand: hand))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(LinearGradient.lit(0.09, 0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        }
        .overlay { SpecularEdge(cornerRadius: Radius.control) }
    }

    private func actionCell(_ binding: GestureBinding) -> some View {
        let action = mappingStore.action(for: binding)
        let isUnassigned = action == .none
        return Button {
            editingBinding = binding
        } label: {
            HStack(spacing: 6) {
                Text(action.displayName)
                    .font(.subheadline)
                    .foregroundStyle(isUnassigned ? .tertiary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(isUnassigned ? 0.3 : 0.8),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1,
                                                                 dash: isUnassigned ? [3, 3] : []))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Edit the action for \(binding.displayName)")
    }
}

/// Sheet for configuring the action assigned to one gesture + hand.
struct ActionEditorView: View {
    let binding: GestureBinding
    let initialAction: GestureAction
    let onSave: (GestureAction) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var kind: GestureAction.Kind = .none

    // Launch app
    @State private var appBundleID = ""
    @State private var appName = ""
    // URL
    @State private var urlString = "https://"
    // Shortcut
    @State private var shortcutName = ""
    @State private var availableShortcuts: [String] = []
    // Keystroke
    @State private var keyCombo = KeyCombo(keyName: "Space", command: true)
    // Hide application
    @State private var hideBundleID = ""
    @State private var hideAppName = ""
    @State private var hideSpecificApp = false
    // Media
    @State private var mediaCommand: MediaCommand = .playPause
    // Macro
    @State private var macroName = ""
    @State private var macroSteps: [MacroStep] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                GestureGlyph(gesture: binding.gesture, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(binding.gesture.displayName).textRole(.title)
                    FieldLabel(binding.hand.displayName)
                }
                Spacer()
            }
            .padding(20)

            Form {
                Picker("Action type", selection: $kind) {
                    ForEach(GestureAction.Kind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }

                switch kind {
                case .none:
                    Text("This gesture will be recognised but won't do anything.")
                        .foregroundStyle(.secondary)

                case .screenshot:
                    Text("Captures the full screen to your Desktop. macOS may ask for Screen Recording permission the first time.")
                        .foregroundStyle(.secondary)

                case .launchApp:
                    LabeledContent("Application") {
                        HStack {
                            Text(appName.isEmpty ? "None selected" : appName)
                                .foregroundStyle(appName.isEmpty ? .secondary : .primary)
                            Button("Choose…", action: chooseApplication)
                        }
                    }

                case .hideApp:
                    Picker("Hide", selection: $hideSpecificApp) {
                        Text("Whatever is in front").tag(false)
                        Text("A specific application").tag(true)
                    }
                    if hideSpecificApp {
                        LabeledContent("Application") {
                            HStack {
                                Text(hideAppName.isEmpty ? "None selected" : hideAppName)
                                    .foregroundStyle(hideAppName.isEmpty ? .secondary : .primary)
                                Button("Choose…", action: chooseHideApplication)
                            }
                        }
                    }
                    Text("Hides the app's windows, recoverable from the Dock. Needs no extra permission.")
                        .font(.caption).foregroundStyle(.secondary)

                case .minimiseWindow:
                    Text("Minimises the frontmost window to the Dock, as the yellow button does. This drives another app's window controls, so it needs Accessibility permission — “Hide Application” achieves something similar without it.")
                        .foregroundStyle(.secondary)

                case .media:
                    Picker("Command", selection: $mediaCommand) {
                        ForEach(MediaCommand.allCases) { command in
                            Label(command.displayName, systemImage: command.symbol).tag(command)
                        }
                    }
                    Text("Sent as a media key, so it reaches whatever is playing — Spotify, Music, a video in your browser — without that app being in front.")
                        .font(.caption).foregroundStyle(.secondary)

                case .openURL:
                    TextField("URL", text: $urlString, prompt: Text("https://calendar.google.com"))
                        .textFieldStyle(.roundedBorder)

                case .runShortcut:
                    if availableShortcuts.isEmpty {
                        TextField("Shortcut name", text: $shortcutName,
                                  prompt: Text("Exactly as named in the Shortcuts app"))
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Shortcut", selection: $shortcutName) {
                            Text("Choose…").tag("")
                            ForEach(availableShortcuts, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }

                case .keystroke:
                    keystrokeEditor

                case .toggleActions:
                    Text("Pauses and resumes every other gesture, so you can use your hands freely without anything firing.\n\nThis gesture keeps working while paused — that's how you switch back on — and it stays quiet in the floating HUD until you use it.")
                        .foregroundStyle(.secondary)

                case .macro:
                    MacroEditorView(name: $macroName, steps: $macroSteps)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(builtAction)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: kind == .macro ? 600 : 460,
               height: kind == .macro ? 620 : 410)
        .onAppear(perform: populateFromInitialAction)
    }

    // MARK: Keystroke editor

    @ViewBuilder
    private var keystrokeEditor: some View {
        LabeledContent("Shortcut") {
            KeyRecorderField(combo: $keyCombo)
        }
        Text("Click the field, then press the key combination you want this gesture to send.")
            .font(.caption).foregroundStyle(.secondary)
        if !ActionExecutor.isAccessibilityTrusted {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Requires Accessibility permission so SayHi can press keys for you.")
                    .font(.caption)
                Button("Grant…") { ActionExecutor.requestAccessibilityPermission() }
                    .controlSize(.small)
            }
        }
    }

    // MARK: State ↔ action conversion

    private func populateFromInitialAction() {
        kind = initialAction.kind
        switch initialAction {
        case .launchApp(let bundleID, let name):
            appBundleID = bundleID
            appName = name
        case .hideApp(let bundleID, let name):
            hideBundleID = bundleID
            hideAppName = name
            hideSpecificApp = !bundleID.isEmpty
        case .media(let command):
            mediaCommand = command
        case .openURL(let url):
            urlString = url
        case .runShortcut(let name):
            shortcutName = name
        case .keystroke(let combo):
            keyCombo = combo
        case .macro(let name, let steps):
            macroName = name
            macroSteps = steps
        default:
            break
        }
        ActionExecutor.availableShortcuts { names in
            availableShortcuts = names
            // Keep a saved-but-deleted shortcut selectable rather than losing it.
            if !shortcutName.isEmpty, !names.contains(shortcutName) {
                availableShortcuts.append(shortcutName)
            }
        }
    }

    private var builtAction: GestureAction {
        switch kind {
        case .none:        return .none
        case .screenshot:  return .screenshot
        case .launchApp:   return .launchApp(bundleID: appBundleID, name: appName)
        case .hideApp:
            return .hideApp(bundleID: hideSpecificApp ? hideBundleID : "",
                            name: hideSpecificApp ? hideAppName : "")
        case .minimiseWindow: return .minimiseWindow
        case .media:       return .media(mediaCommand)
        case .openURL:     return .openURL(urlString)
        case .runShortcut: return .runShortcut(name: shortcutName)
        case .keystroke:   return .keystroke(keyCombo)
        case .macro:       return .macro(name: macroName, steps: macroSteps)
        case .toggleActions: return .toggleActions
        }
    }

    private var isValid: Bool {
        switch kind {
        case .launchApp:
            return !appBundleID.isEmpty
        case .hideApp:
            // "Whatever is in front" needs no target; a specific app does.
            return !hideSpecificApp || !hideBundleID.isEmpty
        case .openURL:
            guard let url = URL(string: urlString) else { return false }
            return url.scheme != nil && url.host != nil
        case .runShortcut:
            return !shortcutName.trimmingCharacters(in: .whitespaces).isEmpty
        case .macro:
            // Every step must actually do something, or the macro silently
            // stops partway through when it runs.
            return !macroSteps.isEmpty && macroSteps.allSatisfy(isStepComplete)
        default:
            return true
        }
    }

    private func isStepComplete(_ step: MacroStep) -> Bool {
        switch step {
        case .typeText(let text):     return !text.isEmpty
        case .launchApp(let id, _):   return !id.isEmpty
        case .openURL(let url):       return URL(string: url)?.host != nil
        case .runShortcut(let name):  return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .hideApp, .minimiseWindow, .media, .keystroke, .delay: return true
        }
    }

    private func chooseHideApplication() {
        guard let picked = ActionEditorView.pickApplication(
            message: "Choose the application this gesture should hide") else { return }
        hideBundleID = picked.bundleID
        hideAppName = picked.name
    }

    /// Shared app chooser, so every picker behaves identically.
    static func pickApplication(message: String) -> (bundleID: String, name: String)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = message
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url) else { return nil }
        let display = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return (bundle.bundleIdentifier ?? "", display)
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the application this gesture should open"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url) else { return }
        appBundleID = bundle.bundleIdentifier ?? ""
        appName = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}
