import SwiftUI

/// The app's Liquid Glass layer.
///
/// Everything visual funnels through the helpers here rather than calling
/// `glassEffect` directly, for two reasons:
///
/// 1. **Deployment target.** The package still targets macOS 14, while the
///    real Liquid Glass API (`glassEffect`, `Glass`, `GlassEffectContainer`,
///    `.buttonStyle(.glass)`) is macOS 26+. Each helper picks the genuine
///    effect where it exists and falls back to a material + hairline rim that
///    reads the same way on 14/15 — so exactly one `#available` check exists
///    per concept instead of one per call site.
/// 2. **Consistency.** Radii, rim opacity and shadow depth are decided once
///    here, so the panels, the HUD and the main window stay a matched set.
///
/// None of this touches recognition, actions or persistence: these are
/// presentation modifiers only.

// MARK: - Tone

/// Which of the two system glass recipes a surface uses.
enum GlassTone {
    /// Chrome that sits over arbitrary content — panels, cards, the HUD.
    case regular
    /// Thinner and more transparent, for chrome laid directly over imagery
    /// (the camera overlay's status strip) where tinting the picture matters
    /// more than legibility of the surface itself.
    case clear

    @available(macOS 26.0, *)
    fileprivate var glass: Glass {
        switch self {
        case .regular: return .regular
        case .clear:   return .clear
        }
    }

    /// Closest pre-26 equivalent.
    fileprivate var material: Material {
        switch self {
        case .regular: return .regularMaterial
        case .clear:   return .ultraThinMaterial
        }
    }
}

// MARK: - Metrics

/// Shared geometry, so nested surfaces stay concentric.
enum GlassMetrics {
    /// Floating panels (cheat sheet, camera overlay).
    static let panelRadius: CGFloat = 22
    /// Cards inside a window (status bar, debug panel).
    static let cardRadius: CGFloat = 16
    /// Controls sitting inside a card.
    static let controlRadius: CGFloat = 10
}

// MARK: - Surface modifier

/// Applies a glass surface behind `content`, clipped to `shape`.
private struct GlassSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var tone: GlassTone
    var tint: Color?
    var interactive: Bool
    /// Fallback-only. On macOS 26 the rim is drawn by `glassEffect` itself and
    /// is not adjustable; there, weight is controlled by keeping the surface
    /// small, since the rim is a fixed width against a variable size.
    var rimWidth: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(resolvedGlass, in: shape)
        } else {
            content
                .background(tone.material, in: shape)
                .overlay(
                    // Liquid Glass's defining edge is a bright top rim fading
                    // to nothing at the bottom; a flat stroke reads as a plain
                    // border, so the fallback fakes the gradient explicitly.
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.06)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: rimWidth)
                )
                .overlay(tint.map { shape.fill($0.opacity(0.22)) })
        }
    }

    @available(macOS 26.0, *)
    private var resolvedGlass: Glass {
        var glass = tone.glass
        if let tint { glass = glass.tint(tint) }
        return glass.interactive(interactive)
    }
}

extension View {

    /// Glass behind this view, clipped to an arbitrary shape.
    ///
    /// - Parameters:
    ///   - interactive: pass `true` only for views that actually receive mouse
    ///     events. Interactive glass reacts to hover and press, which looks
    ///     broken on anything click-through or drag-intercepted.
    func glassSurface<S: InsettableShape>(_ shape: S,
                                          tone: GlassTone = .regular,
                                          tint: Color? = nil,
                                          interactive: Bool = false,
                                          rimWidth: CGFloat = 1) -> some View {
        modifier(GlassSurface(shape: shape, tone: tone, tint: tint,
                              interactive: interactive, rimWidth: rimWidth))
    }

    /// Rounded-rectangle glass — the default for cards and panels.
    func glassCard(radius: CGFloat = GlassMetrics.cardRadius,
                   tone: GlassTone = .regular,
                   tint: Color? = nil,
                   interactive: Bool = false,
                   rimWidth: CGFloat = 1) -> some View {
        glassSurface(RoundedRectangle(cornerRadius: radius, style: .continuous),
                     tone: tone, tint: tint, interactive: interactive, rimWidth: rimWidth)
    }

    /// Pill-shaped glass, for badges, banners and the HUD.
    func glassCapsule(tone: GlassTone = .regular,
                      tint: Color? = nil,
                      interactive: Bool = false,
                      rimWidth: CGFloat = 1) -> some View {
        glassSurface(Capsule(style: .continuous),
                     tone: tone, tint: tint, interactive: interactive, rimWidth: rimWidth)
    }

    /// Tags a glass surface so sibling surfaces in the same `GlassStack` can
    /// morph into one another instead of cross-fading. No-op before macOS 26.
    @ViewBuilder
    func glassMorph(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// The system glass button style where it exists, bordered before that.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }

    /// Drop shadow tuned for a floating glass panel over unknown content.
    func glassShadow(radius: CGFloat = 18, y: CGFloat = 6) -> some View {
        shadow(color: .black.opacity(0.22), radius: radius, y: y)
    }
}

// MARK: - Container

/// Groups nearby glass surfaces so they blend and morph as one system rather
/// than as separate panes stacked on top of each other.
///
/// Falls through to a plain `ZStack`-less passthrough before macOS 26, where
/// there is nothing to coordinate.
struct GlassStack<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Backdrop

/// A soft tinted wash painted behind the main window's content.
///
/// Glass only reads as glass when there is something behind it to bend; over a
/// flat system background every surface collapses into the same grey. This
/// gives the window enough low-frequency colour for the cards to pick up,
/// without competing with them.
///
/// Deliberately static: the app is already spending CPU on per-frame Vision
/// work, and an animated backdrop would compete with it for no real benefit.
struct GlassBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.02)],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            RadialGradient(
                colors: [Color.purple.opacity(0.14), .clear],
                center: .init(x: 0.85, y: 0.1), startRadius: 0, endRadius: 460)

            RadialGradient(
                colors: [Color.teal.opacity(0.12), .clear],
                center: .init(x: 0.1, y: 0.95), startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
