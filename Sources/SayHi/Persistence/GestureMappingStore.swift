import AppKit
import Foundation

/// Persists (gesture, hand) → action mappings as JSON in Application Support.
/// Loads on init, saves on every change.
///
/// On disk the keys are flat strings like `"fist.left"`, which keeps the file
/// readable and makes adding gestures or hands a non-breaking change.
@MainActor
final class GestureMappingStore: ObservableObject {

    @Published private(set) var mappings: [GestureBinding: GestureAction] = [:]

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SayHi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("mappings.json")
        load()
    }

    func action(for binding: GestureBinding) -> GestureAction {
        mappings[binding] ?? .none
    }

    func action(for gesture: Gesture, hand: HandSide) -> GestureAction {
        action(for: GestureBinding(gesture: gesture, hand: hand))
    }

    func setAction(_ action: GestureAction, for binding: GestureBinding) {
        mappings[binding] = action
        save()
    }

    /// Number of gestures wired up, for the summary line in the UI.
    var assignedCount: Int {
        mappings.values.filter { $0 != .none }.count
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            mappings = Self.defaultMappings()
            save()
            return
        }
        let decoder = JSONDecoder()

        // Current format: ["fist.left": action, …]
        if let stored = try? decoder.decode([String: GestureAction].self, from: data) {
            mappings = stored.reduce(into: [:]) { result, entry in
                if let binding = GestureBinding(id: entry.key) { result[binding] = entry.value }
            }
            seedMissingDefaults()
            return
        }

        // Pre-handedness format keyed by gesture alone. Migrate by giving both
        // hands the action the user had already chosen, so nothing is lost.
        if let legacy = try? decoder.decode([Gesture: GestureAction].self, from: data) {
            for (gesture, action) in legacy {
                for hand in HandSide.allCases {
                    mappings[GestureBinding(gesture: gesture, hand: hand)] = action
                }
            }
            seedMissingDefaults()
            save()
            return
        }

        mappings = Self.defaultMappings()
        save()
    }

    private func save() {
        let encodable = mappings.reduce(into: [String: GestureAction]()) { result, entry in
            result[entry.key.id] = entry.value
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(encodable) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Fills in defaults only for gestures that have *no entry at all* — i.e.
    /// ones introduced after this mappings file was written. A gesture the
    /// user deliberately set to "Unassigned" has an entry, so it is left alone.
    /// This is what makes a newly added gesture work out of the box without
    /// overwriting anything already chosen.
    private func seedMissingDefaults() {
        var changed = false
        for (binding, action) in Self.defaultMappings() where mappings[binding] == nil {
            mappings[binding] = action
            changed = true
        }
        if changed { save() }
    }

    // MARK: - First-run defaults

    /// Fist → screenshot; open palm → Chrome if installed, else Safari.
    /// Both hands get the same defaults — handedness is opt-in, discovered by
    /// assigning something different to the other hand.
    private static func defaultMappings() -> [GestureBinding: GestureAction] {
        let browser: GestureAction
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil {
            browser = .launchApp(bundleID: "com.google.Chrome", name: "Google Chrome")
        } else {
            browser = .launchApp(bundleID: "com.apple.Safari", name: "Safari")
        }

        var defaults: [GestureBinding: GestureAction] = [:]
        for hand in HandSide.allCases {
            defaults[GestureBinding(gesture: .fist, hand: hand)] = .screenshot
            defaults[GestureBinding(gesture: .openPalm, hand: hand)] = browser
            // Deliberate and rare enough not to happen by accident, which is
            // what a pause switch needs.
            defaults[GestureBinding(gesture: .callMe, hand: hand)] = .toggleActions
        }
        return defaults
    }
}
