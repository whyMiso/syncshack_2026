import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        TabView {
            RecognitionView()
                .tabItem { Label("Camera", systemImage: "camera") }
            MappingsView()
                .tabItem { Label("Gestures", systemImage: "hand.raised") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 16) {
                    Toggle(isOn: $app.isEnabled) {
                        Text("Gesture Control: \(app.isEnabled ? "ON" : "OFF")")
                            .fontWeight(.semibold)
                    }
                    .toggleStyle(.switch)
                    .help("Turns the camera and recognition on or off")

                    Divider().frame(height: 16)

                    Toggle(isOn: $settings.actionsEnabled) {
                        Text("Actions: \(settings.actionsEnabled ? "ON" : "OFF")")
                            .fontWeight(.semibold)
                            .foregroundStyle(settings.actionsEnabled ? Color.primary : Color.orange)
                    }
                    .toggleStyle(.switch)
                    .help("Keeps recognising gestures but stops them running anything")
                }
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}
