import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore

    @State private var tab: Tab = .camera

    enum Tab: String, CaseIterable, Identifiable {
        case camera, gestures, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .camera:   return "Camera"
            case .gestures: return "Gestures"
            case .settings: return "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .camera:   return "camera"
            case .gestures: return "hand.raised"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .background {
                    // The header catches the light first, so it sits a step
                    // brighter than the body of the window.
                    LinearGradient.lit(0.05, 0.0)
                }
                .overlay(alignment: .bottom) { Hairline() }

            Group {
                switch tab {
                case .camera:   RecognitionView()
                case .gestures: MappingsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
                .background { WindowSurface() }
        .preferredColorScheme(.dark)
        .frame(minWidth: 820, minHeight: 580)
    }

    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 9) {
                AppMark()
                Text("SayHi")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink)
            }

            Spacer(minLength: 8)

            TabStrip(selection: $tab)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                ToggleChip(title: "Recognition", isOn: app.isEnabled) {
                    app.isEnabled.toggle()
                }
                .help("Turns the camera and recognition on or off")

                ToggleChip(title: "Actions",
                           isOn: settings.actionsEnabled,
                           enabled: app.isEnabled) {
                    settings.actionsEnabled.toggle()
                }
                .help("Keeps recognising gestures but stops them running anything")
            }
        }
        // Leading room for the traffic lights, which float over the content
        // now that the system title bar is hidden.
        .padding(.leading, 78)
        .padding(.trailing, 16)
        .frame(height: 56)
    }
}

/// Segmented navigation. Selection is shown by fill and text opacity — the
/// accent stays reserved for actions that do something.
private struct TabStrip: View {
    @Binding var selection: ContentView.Tab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ContentView.Tab.allCases) { tab in
                Segment(tab: tab,
                        selected: selection == tab) { selection = tab }
            }
        }
        .padding(3)
        .background {
            // Recessed well: darker than the surface, so the selected segment
            // above it reads as raised rather than merely tinted.
            RoundedRectangle(cornerRadius: Radius.control + 3, style: .continuous)
                .fill(Color.black.opacity(0.18))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control + 3, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        }
    }

    private struct Segment: View {
        let tab: ContentView.Tab
        let selected: Bool
        let action: () -> Void

        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .medium))
                    Text(tab.title)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(selected ? Palette.ink : Palette.inkMuted)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(selected ? AnyShapeStyle(LinearGradient.lit(0.13, 0.06))
                              : AnyShapeStyle(hovering ? Palette.fillHover : .clear))
                }
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                        SpecularEdge(cornerRadius: Radius.control)
                    }
                }
                .shadow(color: .black.opacity(selected ? 0.28 : 0), radius: 3, y: 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
        }
    }
}
