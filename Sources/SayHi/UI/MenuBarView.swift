import SwiftUI

/// Menu bar dropdown: status, enable/disable, pause actions, settings, quit.
struct MenuBarView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)

        Divider()

        if app.isEnabled {
            Button("Disable Gesture Control") { app.isEnabled = false }
        } else {
            Button("Enable Gesture Control") { app.isEnabled = true }
        }

        if settings.actionsEnabled {
            Button("Pause Actions (keep watching)") { settings.actionsEnabled = false }
        } else {
            Button("Resume Actions") { settings.actionsEnabled = true }
        }

        Divider()

        Button("Show Gesture List (\(settings.cheatSheetHotKey.displayString))") {
            app.toggleCheatSheet()
        }

        Button(settings.cameraOverlayVisible
               ? "Hide Camera Overlay (\(settings.cameraOverlayHotKey.displayString))"
               : "Show Camera Overlay (\(settings.cameraOverlayHotKey.displayString))") {
            app.toggleCameraOverlay()
        }

        Button("Open Settings…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit SayHi") {
            NSApp.terminate(nil)
        }
    }

    private var statusLine: String {
        guard app.isEnabled else { return "Gesture Control: Paused" }
        return settings.actionsEnabled
            ? "Gesture Control: Active"
            : "Gesture Control: Watching (actions paused)"
    }
}
