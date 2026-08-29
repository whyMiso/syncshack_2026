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
                HStack(spacing: 9) {
                    // The ": ON"/": OFF" suffixes are gone: at this size the
                    // switch already states its position, and the extra words
                    // are what pushed the cluster past the width the toolbar
                    // will give it — at which point SwiftUI drops the labels
                    // entirely and leaves two anonymous switches.
                    Toggle(isOn: $app.isEnabled) {
                        Text("Gesture Control")
                    }
                    .help("Turns the camera and recognition on or off")

                    Divider().frame(height: 12)

                    Toggle(isOn: $settings.actionsEnabled) {
                        Text("Actions")
                            .foregroundStyle(settings.actionsEnabled ? Color.primary : Color.orange)
                    }
                    .help("Keeps recognising gestures but stops them running anything")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.subheadline)
                // Sized to its content, so if the toolbar ever does run short
                // of room the cluster is clipped visibly rather than quietly
                // shedding its labels.
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                // Clear, not regular: on macOS 26 the toolbar is already a
                // pane of glass, and a second regular layer inside it reads as
                // a smudge. Clear just groups the two switches as one control.
                //
                // The rim is the other half of "chunky": on 26 `glassEffect`
                // draws it at a fixed width, so the only lever is keeping the
                // surface small — hence the tighter padding above. `rimWidth`
                // thins the pre-26 fallback to match.
                .glassCapsule(tone: .clear, rimWidth: 0.5)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}
