import AppKit
import SwiftUI

/// Builds an ordered list of macro steps: type text, press keys, wait, and so on.
struct MacroEditorView: View {
    @Binding var name: String
    @Binding var steps: [MacroStep]

    var body: some View {
        LabeledContent("Name") {
            TextField("", text: $name, prompt: Text("e.g. Reply to email"))
                .textFieldStyle(.roundedBorder)
        }

        ForEach(steps.indices, id: \.self) { index in
            stepRow(index)
        }

        HStack {
            Menu {
                ForEach(MacroStep.Kind.allCases) { kind in
                    Button(kind.rawValue) { steps.append(.empty(kind)) }
                }
            } label: {
                Label("Add step", systemImage: "plus")
            }
            .frame(width: 130)

            Spacer()

            if !steps.isEmpty {
                Text(estimate).font(.caption).foregroundStyle(.secondary)
            }
        }

        if steps.contains(where: isTypingStep) {
            Label("Typed text goes to whichever app is frontmost when the gesture fires. Don't store passwords here — mappings are saved as plain text.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: One step

    @ViewBuilder
    private func stepRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(index + 1).")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .trailing)

                Picker("", selection: kindBinding(index)) {
                    ForEach(MacroStep.Kind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                Spacer()

                Button { steps.swapAt(index, index - 1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0)
                Button { steps.swapAt(index, index + 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == steps.count - 1)
                Button(role: .destructive) { steps.remove(at: index) } label: { Image(systemName: "trash") }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            configuration(index).padding(.leading, 24)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func configuration(_ index: Int) -> some View {
        switch steps[index] {
        case .typeText:
            TextField("", text: textBinding(index), prompt: Text("Text to type"), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...8)

        case .keystroke:
            KeyRecorderField(combo: comboBinding(index), placeholder: "Press keys…")

        case .delay:
            HStack(spacing: 6) {
                TextField("", value: delayBinding(index), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("seconds").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }

        case .launchApp(_, let appName):
            HStack {
                Text(appName.isEmpty ? "No application chosen" : appName)
                    .foregroundStyle(appName.isEmpty ? .secondary : .primary)
                Button("Choose…") { chooseApplication(for: index) }
                    .controlSize(.small)
                Spacer()
            }

        case .hideApp(let bundleID, let appName):
            HStack(spacing: 8) {
                Text(bundleID.isEmpty ? "Whatever is in front" : appName)
                    .foregroundStyle(bundleID.isEmpty ? .secondary : .primary)
                Button("Front app") { steps[index] = .hideApp(bundleID: "", name: "") }
                    .disabled(bundleID.isEmpty)
                Button("Choose…") {
                    if let picked = ActionEditorView.pickApplication(
                        message: "Choose the application this step should hide") {
                        steps[index] = .hideApp(bundleID: picked.bundleID, name: picked.name)
                    }
                }
                Spacer()
            }
            .controlSize(.small)

        case .media:
            Picker("", selection: mediaBinding(index)) {
                ForEach(MediaCommand.allCases) { command in
                    Text(command.displayName).tag(command)
                }
            }
            .labelsHidden()
            .frame(width: 180)

        case .tileWindow:
            Picker("", selection: tileBinding(index)) {
                ForEach(TileArrangement.allCases) { a in
                    Text(a.displayName).tag(a)
                }
            }
            .labelsHidden()
            .frame(width: 200)

        case .minimiseWindow:
            Text("Minimises the frontmost window to the Dock. Needs Accessibility permission.")
                .font(.caption).foregroundStyle(.secondary)

        case .openURL:
            TextField("", text: urlBinding(index), prompt: Text("https://…"))
                .textFieldStyle(.roundedBorder)

        case .runShortcut:
            TextField("", text: shortcutBinding(index),
                      prompt: Text("Shortcut name, exactly as in the Shortcuts app"))
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: Bindings into the step array
    //
    // Each step carries a different payload, so reading one means matching its
    // case; writing replaces the whole step.

    private func kindBinding(_ index: Int) -> Binding<MacroStep.Kind> {
        Binding(get: { steps[index].kind },
                set: { newKind in
                    guard newKind != steps[index].kind else { return }
                    steps[index] = .empty(newKind)
                })
    }

    private func textBinding(_ index: Int) -> Binding<String> {
        Binding(get: { if case .typeText(let t) = steps[index] { return t }; return "" },
                set: { steps[index] = .typeText($0) })
    }

    private func urlBinding(_ index: Int) -> Binding<String> {
        Binding(get: { if case .openURL(let u) = steps[index] { return u }; return "" },
                set: { steps[index] = .openURL($0) })
    }

    private func shortcutBinding(_ index: Int) -> Binding<String> {
        Binding(get: { if case .runShortcut(let n) = steps[index] { return n }; return "" },
                set: { steps[index] = .runShortcut(name: $0) })
    }

    private func delayBinding(_ index: Int) -> Binding<Double> {
        Binding(get: { if case .delay(let s) = steps[index] { return s }; return 0 },
                set: { steps[index] = .delay(max(0, min($0, 30))) })
    }

    private func mediaBinding(_ index: Int) -> Binding<MediaCommand> {
        Binding(get: { if case .media(let c) = steps[index] { return c }; return .playPause },
                set: { steps[index] = .media($0) })
    }

    private func tileBinding(_ index: Int) -> Binding<TileArrangement> {
        Binding(get: { if case .tileWindow(let a) = steps[index] { return a }; return .leftAndRight },
                set: { steps[index] = .tileWindow($0) })
    }

    private func comboBinding(_ index: Int) -> Binding<KeyCombo> {
        Binding(get: { if case .keystroke(let c) = steps[index] { return c }
                       return KeyCombo(keyName: "Return") },
                set: { steps[index] = .keystroke($0) })
    }

    private func chooseApplication(for index: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.message = "Choose the application this step should open"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url) else { return }
        let display = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        steps[index] = .launchApp(bundleID: bundle.bundleIdentifier ?? "", name: display)
    }

    // MARK: Estimate

    private func isTypingStep(_ step: MacroStep) -> Bool {
        if case .typeText = step { return true }
        return false
    }

    /// Rough run time: typed text is posted in 20-character chunks ~10 ms apart.
    private var estimate: String {
        var seconds = 0.0
        for step in steps {
            switch step {
            case .typeText(let text): seconds += Double(text.count) / 20.0 * 0.01
            case .delay(let value):   seconds += value
            default:                  seconds += 0.05
            }
        }
        return String(format: "%d step%@ · about %.1fs", steps.count,
                      steps.count == 1 ? "" : "s", seconds)
    }
}
