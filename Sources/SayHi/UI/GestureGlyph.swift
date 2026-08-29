import SwiftUI

/// The mark shown for a gesture: the system emoji, fully desaturated.
///
/// Apple's hand emoji are better drawn than anything hand-rolled at this size,
/// but in colour they fight everything around them — the panel is white at a
/// few fixed opacities and one blue. Stripping the saturation keeps the
/// drawing and drops the argument; a small brightness and contrast lift stops
/// the result reading as a grey smudge on a dark surface.
struct GestureGlyph: View {
    let gesture: Gesture
    var size: CGFloat = 18

    var body: some View {
        Text(gesture.symbol)
            // Emoji sit inside a box a little taller than their point size,
            // so the font is stepped down to land in the frame we reserve.
            .font(.system(size: size * 0.84))
            .grayscale(1)
            .brightness(0.10)
            .contrast(1.08)
            .frame(width: size, height: size)
    }
}
