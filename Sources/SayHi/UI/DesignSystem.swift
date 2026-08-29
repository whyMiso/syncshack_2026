import SwiftUI

// MARK: - Palette
//
// One near-black base, one accent, and white at fixed opacities for everything
// else. If a new hue seems necessary, the answer is a different opacity or a
// different shape — not a second colour.

enum Palette {
    /// Near-black, not black: #0A0A0B. Pure black kills the material.
    static let base = Color(red: 0.039, green: 0.039, blue: 0.043)

    /// The single accent. Reserved for the primary action.
    static let accent = Color(red: 0.043, green: 0.518, blue: 1.0)

    static let ink      = Color.white.opacity(0.88)   // body
    static let inkMuted = Color.white.opacity(0.55)   // secondary
    static let inkFaint = Color.white.opacity(0.38)   // tertiary — the floor

    static let hairline  = Color.white.opacity(0.12)  // inner stroke
    static let specular  = Color.white.opacity(0.22)  // top edge only
    static let fillHover = Color.white.opacity(0.06)
    static let fillInset = Color.white.opacity(0.05)
}

// MARK: - Geometry

enum Radius {
    static let panel: CGFloat = 20
    static let compact: CGFloat = 16   // HUD, camera overlay
    static let chip: CGFloat = 10
    static let control: CGFloat = 8

    /// Concentric radius for a child inset by `inset` inside a `parent` corner.
    /// Keeps curves parallel instead of merely "both rounded".
    static func nested(in parent: CGFloat, inset: CGFloat) -> CGFloat {
        max(2, parent - inset)
    }
}

enum Layout {
    /// Room a hosted panel must leave around its content for the ambient
    /// shadow, which is drawn by SwiftUI rather than by the NSPanel.
    static let shadowInset = EdgeInsets(top: 28, leading: 36, bottom: 52, trailing: 36)

    static var shadowWidth: CGFloat { shadowInset.leading + shadowInset.trailing }
    static var shadowHeight: CGFloat { shadowInset.top + shadowInset.bottom }

    /// Same idea for chips, which are small enough that a full-size ambient
    /// shadow would be a bigger halo than the thing casting it.
    static let chipInset = EdgeInsets(top: 12, leading: 18, bottom: 26, trailing: 18)

    static var chipWidth: CGFloat { chipInset.leading + chipInset.trailing }
    static var chipHeight: CGFloat { chipInset.top + chipInset.bottom }
}

enum Motion {
    /// Enter: opacity 0→1, scale 0.98→1.
    static let enter = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.18)
    /// Hover: background only, never scale.
    static let hover = Animation.easeOut(duration: 0.12)
    /// A chunk of text arriving. Fade, no jitter.
    static let chunk = Animation.easeOut(duration: 0.1)
}

// MARK: - Type
//
// Four sizes, two weights. 11 uppercase label / 13 UI / 15 primary / 22 title.

enum TextRole {
    case label          // 11, uppercase, tracked, secondary
    case body           // 13
    case bodyEmphasis   // 13 medium
    case primary        // 15, line-height 1.5
    case title          // 22
}

private struct TextRoleModifier: ViewModifier {
    let role: TextRole
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        switch role {
        case .label:
            content
                .font(.system(size: 11, weight: .medium))
                .tracking(0.88)                       // 0.08em
                .foregroundStyle(tint ?? Palette.inkMuted)
        case .body:
            content
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(tint ?? Palette.ink)
        case .bodyEmphasis:
            content
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint ?? Palette.ink)
        case .primary:
            content
                .font(.system(size: 15, weight: .regular))
                .tracking(-0.15)                      // -0.01em
                .lineSpacing(4.5)                     // → line-height ≈ 1.5
                .foregroundStyle(tint ?? Palette.ink)
        case .title:
            content
                .font(.system(size: 22, weight: .medium))
                .tracking(-0.22)
                .foregroundStyle(tint ?? Palette.ink)
        }
    }
}

extension View {
    func textRole(_ role: TextRole, tint: Color? = nil) -> some View {
        modifier(TextRoleModifier(role: role, tint: tint))
    }
}

/// An 11px uppercase label. Takes the string rather than a `Text` so the
/// uppercasing can't be forgotten at a call site.
struct FieldLabel: View {
    let text: String
    var tint: Color = Palette.inkMuted

    init(_ text: String, tint: Color = Palette.inkMuted) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text.uppercased()).textRole(.label, tint: tint)
    }
}

// MARK: - The glass
//
// Built in layers rather than as one blur, because a single blur reads as a
// sheet of plastic. Bottom to top: blurred backdrop, dark scrim, a white
// gradient standing in for a light source, then the edges.

/// Depth is always two shadows: a tight contact shadow that seats the panel,
/// and a wide ambient one that lifts it. One shadow alone reads as a sticker.
enum SurfaceDepth {
    case standing   // full-size panel
    case compact    // chips and small overlays
    case none       // drawn inside something that casts its own

    var contact: (Color, CGFloat, CGFloat) {
        switch self {
        case .none: return (.clear, 0, 0)
        default:    return (.black.opacity(0.26), 2, 1)
        }
    }

    // Softened from the reference spec's 0/24/64 · 0.44. That value is tuned
    // for dark and photographic backdrops; these panels also float over white
    // documents, where a 32-radius 44%-black shadow spreads into a grey slab
    // rather than a lift. A tighter, lighter ambient reads as depth on both.
    var ambient: (Color, CGFloat, CGFloat) {
        switch self {
        case .standing: return (.black.opacity(0.24), 20, 12)
        case .compact:  return (.black.opacity(0.22), 11, 7)
        case .none:     return (.clear, 0, 0)
        }
    }
}

struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Radius.panel
    /// Dark scrim opacity. This — not the text opacity — is the dial to turn
    /// when the panel sits over something bright.
    var scrim: Double = 0.5
    var depth: SurfaceDepth = .standing

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background {
                // The two shadows are cast by the *shape* — via ShapeStyle drop
                // shadows on the base fill — not by a `.shadow()` on a
                // compositing group wrapping the view. That distinction matters:
                // `.ultraThinMaterial` inside a shadow-casting compositing group
                // has no backdrop to sample when it's rasterized offscreen, so it
                // casts a displaced *opaque* copy of itself — the grey slab —
                // instead of a soft blur. A drop shadow on the shape's own fill
                // uses the shape geometry as the caster and never does this.
                shape
                    .fill(.ultraThinMaterial
                        .shadow(.drop(color: depth.contact.0,
                                      radius: depth.contact.1, y: depth.contact.2))
                        .shadow(.drop(color: depth.ambient.0,
                                      radius: depth.ambient.1, y: depth.ambient.2)))
                    .overlay { shape.fill(Palette.base.opacity(scrim)) }
                    .overlay {
                        // The light source. Most of the "premium" read lives here.
                        shape.fill(LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.06), location: 0),
                                .init(color: .white.opacity(0.015), location: 0.35),
                                .init(color: .white.opacity(0),    location: 0.8),
                            ],
                            startPoint: .top, endPoint: .bottom))
                    }
                    .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 1) }
                    .overlay { SpecularEdge(cornerRadius: cornerRadius) }
                    .environment(\.colorScheme, .dark)
            }
    }
}

/// A brighter 1px line along the top edge only, fading out toward both
/// corners. Small detail, disproportionate effect: without it the surface
/// reads flat no matter how good the blur is.
struct SpecularEdge: View {
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geo in
            // Falloff is expressed in points, then converted, so a tall panel
            // doesn't end up with its whole upper flank lit.
            let falloff = min(0.5, 20 / max(geo.size.height, 1))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Palette.specular, location: 0),
                            .init(color: .white.opacity(0.05), location: falloff * 0.45),
                            .init(color: .white.opacity(0), location: falloff),
                        ],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: 0.22),
                            .init(color: .white, location: 0.78),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing)
                }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = Radius.panel,
                      scrim: Double = 0.5,
                      depth: SurfaceDepth = .standing) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, scrim: scrim, depth: depth))
    }

    /// Enter transition shared by every floating surface.
    func panelEntrance(_ shown: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.98)
            .animation(Motion.enter, value: shown)
    }
}

/// The real thing behind the window: an `NSVisualEffectView` blending with
/// what is *behind* the window, which is what makes the desktop show through
/// and get blurred. A SwiftUI `.background(.ultraThinMaterial)` only samples
/// inside the window, so on its own it can never look like glass.
struct WindowMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        // Stays lit when the window is not key; a surface that goes flat on
        // focus loss reads as a screenshot of glass rather than glass.
        view.state = .active
    }
}

/// The window's own surface: the same four layers as a floating panel, minus
/// the corner radius and shadow, which the window itself provides.
struct WindowSurface: View {
    var scrim: Double = 0.50

    var body: some View {
        ZStack {
            WindowMaterial()
            Palette.base.opacity(scrim)
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.055), location: 0),
                    .init(color: .white.opacity(0.018), location: 0.22),
                    .init(color: .white.opacity(0), location: 0.6),
                ],
                startPoint: .top, endPoint: .bottom)
        }
        .overlay(alignment: .top) { TopSpecular() }
        .ignoresSafeArea()
    }
}

/// The bright line along the very top of a surface, fading out toward both
/// ends. One pixel, and it does more for the glass read than the blur does.
struct TopSpecular: View {
    var opacity: Double = 0.26

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(opacity), location: 0.2),
                .init(color: .white.opacity(opacity), location: 0.8),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing)
        .frame(height: 1)
        .allowsHitTesting(false)
    }
}

/// Top-lit fill used by raised elements — cards, the header strip, a selected
/// segment. Light comes from above, so the top edge is brighter.
extension LinearGradient {
    static func lit(_ top: Double, _ bottom: Double) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(top), location: 0),
                .init(color: .white.opacity((top + bottom) / 2), location: 0.45),
                .init(color: .white.opacity(bottom), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
    }
}

/// A full-bleed 1px rule. `Divider` picks up system colours we don't want.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
    }
}

// MARK: - Controls

/// Text button. Ghost by default; `accent` is the one primary action per panel.
struct PanelButton: View {
    enum Kind { case ghost, accent }

    let title: String
    var icon: String?
    var kind: Kind = .ghost
    var enabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(background)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(kind == .accent ? Color.clear : Palette.hairline,
                                  lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }

    private var foreground: Color {
        guard enabled else { return Palette.inkFaint }
        return kind == .accent ? .white : Palette.ink
    }

    private var background: Color {
        switch kind {
        case .accent:
            return enabled ? Palette.accent : Palette.fillInset
        case .ghost:
            return hovering && enabled ? Palette.fillHover : .clear
        }
    }
}

/// Square icon button — close, and other single-glyph controls.
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 13
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(hovering ? Palette.ink : Palette.inkMuted)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(hovering ? Palette.fillHover : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

/// The app mark: a small inset tile, not a logo.
struct AppMark: View {
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let paw = AppMark.paw {
                // The brand paw. A faint white shadow lifts the glass off the
                // dark header the same way the app icon's glow does.
                Image(nsImage: paw)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: size)
                    .shadow(color: .white.opacity(0.25), radius: size * 0.14)
            } else {
                // Fallback for `swift run` (no bundled resource): the old tile.
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(LinearGradient.lit(0.12, 0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    }
                    .overlay { SpecularEdge(cornerRadius: Radius.control) }
                    .overlay {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: size * 0.5, weight: .regular))
                            .foregroundStyle(Palette.ink)
                    }
                    .frame(width: size, height: size)
            }
        }
    }

    /// Loaded once from the app bundle's Resources (copied there by build.sh).
    static let paw: NSImage? = {
        guard let url = Bundle.main.url(forResource: "paw-mark", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

/// State dot. Distinguishes states by fill and opacity rather than by hue,
/// and never travels without its label.
struct StateDot: View {
    enum Level { case on, muted, off }

    let level: Level

    var body: some View {
        Group {
            switch level {
            case .on:
                Circle().fill(Palette.ink)
            case .muted:
                Circle().strokeBorder(Palette.inkMuted, lineWidth: 1.5)
            case .off:
                Circle().strokeBorder(Palette.inkFaint, lineWidth: 1.5)
            }
        }
        .frame(width: 7, height: 7)
    }
}

/// Input field with a send affordance. The field filters the list; the
/// affordance is the panel's single primary action.
struct PanelField: View {
    @Binding var text: String
    var placeholder: String
    var sendSymbol: String = "arrow.up.right"
    var sendHelp: String = ""
    let onSend: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.inkFaint)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.inkFaint)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                    .focused($focused)
                    .onSubmit(onSend)
            }

            if !text.isEmpty {
                IconButton(symbol: "xmark.circle.fill", size: 12, help: "Clear") {
                    text = ""
                }
            }

            SendButton(symbol: sendSymbol, help: sendHelp, action: onSend)
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: 36)
        .background {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Palette.fillInset)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(focused ? Color.white.opacity(0.22) : Palette.hairline,
                              lineWidth: 1)
        }
        .animation(Motion.hover, value: focused)
        .onTapGesture { focused = true }
    }
}

private struct SendButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.accent)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(hovering ? Palette.fillHover : .clear)
                        }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

/// A two-state control shown as a dot plus a label. Reads as on/off without
/// needing a second colour, and keeps its meaning at a glance from across
/// the room — which is the point of a gesture app's status.
struct ToggleChip: View {
    let title: String
    let isOn: Bool
    var enabled: Bool = true
    var showsDot: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if showsDot {
                    StateDot(level: enabled ? (isOn ? .on : .muted) : .off)
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(enabled ? (isOn ? Palette.ink : Palette.inkMuted)
                                             : Palette.inkFaint)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isOn && enabled ? AnyShapeStyle(LinearGradient.lit(0.22, 0.11))
                          : AnyShapeStyle(hovering && enabled ? Palette.fillHover : .clear))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            .overlay { SpecularEdge(cornerRadius: Radius.control) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

/// A pane inside the window. Two kinds, because not everything on a surface
/// sits *on* it: a status bar is an object resting on the glass, while a
/// camera viewport is a hole cut into it. Raised elements are lit from above
/// and cast a shadow; recessed ones are darker and catch their light on the
/// bottom edge, with the shadow falling inward.
struct InsetCard<Content: View>: View {
    enum Style { case raised, recessed }

    var cornerRadius: CGFloat = 12
    var style: Style = .raised
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        switch style {
        case .raised:
            content
                .background { shape.fill(LinearGradient.lit(0.11, 0.03)) }
                .clipShape(shape)
                .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 1) }
                .overlay { SpecularEdge(cornerRadius: cornerRadius) }
                .compositingGroup()
                .shadow(color: .black.opacity(0.32), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.34), radius: 16, y: 9)
        case .recessed:
            content
                .background {
                    // Dark enough to read as a well, translucent enough that
                    // the glass still carries through it.
                    shape.fill(Color.black.opacity(0.16)
                        .shadow(.inner(color: .black.opacity(0.55), radius: 10, y: 5)))
                }
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.09), lineWidth: 1) }
                .overlay { BottomSheen(cornerRadius: cornerRadius) }
        }
    }
}

/// The counterpart to `SpecularEdge` for recessed elements: light pools on the
/// lower lip of a well, not the top.
struct BottomSheen: View {
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geo in
            let falloff = min(0.5, 18 / max(geo.size.height, 1))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: 1 - falloff),
                            .init(color: .white.opacity(0.05), location: 1 - falloff * 0.45),
                            .init(color: .white.opacity(0.16), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: 0.22),
                            .init(color: .white, location: 0.78),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing)
                }
        }
        .allowsHitTesting(false)
    }
}

/// A switch. On is a filled white track with a dark knob cut out of it, off is
/// a dim well — state reads from fill and contrast rather than from a colour,
/// like everything else here.
struct SwitchControl: View {
    @Binding var isOn: Bool
    var enabled: Bool = true

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.white.opacity(enabled ? 0.85 : 0.22)
                               : Color.black.opacity(0.32))
                    .overlay { Capsule().strokeBorder(Palette.hairline, lineWidth: 1) }
                Circle()
                    .fill(isOn ? Palette.base : Color.white.opacity(enabled ? 0.55 : 0.22))
                    .frame(width: 15, height: 15)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                    .padding(3)
            }
            .frame(width: 38, height: 21)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(Motion.hover, value: isOn)
    }
}

/// A pop-up menu wearing the same clothes as the buttons, so a settings page
/// doesn't turn into a strip of system popup buttons.
struct MenuChip<T: Hashable>: View {
    let options: [T]
    let title: (T) -> String
    @Binding var selection: T
    var enabled: Bool = true

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(title(option)) { selection = option }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title(selection)).font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.inkMuted)
            }
            .foregroundStyle(enabled ? Palette.ink : Palette.inkFaint)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(LinearGradient.lit(0.10, 0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            .overlay { SpecularEdge(cornerRadius: Radius.control) }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!enabled)
    }
}
