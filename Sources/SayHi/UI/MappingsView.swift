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
        ZStack {
            GlassBackdrop()

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

                Divider()
                Text("Hand recognition runs entirely on this Mac. Camera images are not stored or transmitted.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            }
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
            Text("Gesture")
                .frame(width: gestureColumnWidth, alignment: .leading)
            ForEach(HandSide.allCases) { hand in
                Label("\(hand.symbol) \(hand.displayName)", systemImage: "")
                    .labelStyle(.titleOnly)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        // Clear glass rather than `.bar`: the header is pinned over a
        // scrolling list, and the rows should be visible sliding under it.
        .glassSurface(Rectangle(), tone: .clear)
    }

    private func row(for gesture: Gesture) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(gesture.symbol).font(.title3)
                Text(gesture.displayName)
                    .font(.subheadline).fontWeight(.medium)
                    .lineLimit(1)
            }
            .frame(width: gestureColumnWidth, alignment: .leading)

            ForEach(HandSide.allCases) { hand in
                actionCell(GestureBinding(gesture: gesture, hand: hand))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .glassCard(radius: GlassMetrics.controlRadius, tone: .clear)
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
            // Assigned cells get full glass, unassigned ones the thinner
            // clear recipe — the same "filled vs empty" read the old opacity
            // pair gave, in glass terms. Interactive here and nowhere else in
            // the app, because this is the one glass surface that is a button.
            .glassCard(radius: 8, tone: isUnassigned ? .clear : .regular, interactive: true)
            .overlay(
                // Glass alone reads as a filled control either way, so the
                // dashed cue for "nothing bound here" has to stay.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.secondary.opacity(isUnassigned ? 0.45 : 0),
                                  style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
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
            HStack(spacing: 10) {
                Text(binding.gesture.symbol).font(.title)
                VStack(alignment: .leading, spacing: 1) {
                    Text(binding.gesture.displayName).font(.title2).bold()
                    Text("\(binding.hand.symbol) \(binding.hand.displayName)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

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

                case .stopCamera:
                    Label("This one is deliberately one-way.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                    Text("Stops the camera and recognition outright — the same switch as “Gesture Control: OFF” in the toolbar. The camera light goes out.\n\nWith the camera off nothing can see your hands, so no gesture can bring it back. Switch it on again from the menu bar (the hand icon) or this window's toolbar. Unlike “Pause / Resume Gestures”, this one is also skipped while actions are paused.")
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
        Picker("Key", selection: $keyCombo.keyName) {
            ForEach(KeyCombo.orderedKeyNames, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        HStack(spacing: 14) {
            Toggle("⌘", isOn: $keyCombo.command)
            Toggle("⇧", isOn: $keyCombo.shift)
            Toggle("⌥", isOn: $keyCombo.option)
            Toggle("⌃", isOn: $keyCombo.control)
        }
        .toggleStyle(.button)
        LabeledContent("Will press", value: keyCombo.displayString)
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
        case .stopCamera:  return .stopCamera
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
