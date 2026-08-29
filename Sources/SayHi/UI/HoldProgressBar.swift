import SwiftUI

/// A hold-to-trigger bar that fills smoothly, tracks in real time, and
/// actually reaches 100%.
///
/// Two things had to be avoided to make this feel immediate:
///
/// 1. **Sampled values.** Gestures are only classified at the analysis frame
///    rate (~12 fps), so a bar bound to the state machine's `holdProgress`
///    steps visibly and its last sample before firing lands near 90%. The
///    value here is derived from the hold's start time and recomputed at
///    display rate instead.
/// 2. **`ProgressView`.** On macOS it is backed by `NSProgressIndicator`,
///    which animates internally toward whatever value it was last handed.
///    Given a new value every frame, the drawn fill perpetually trails the
///    real one — it reads as lag. The fill is drawn directly below so the
///    geometry is exactly the value asked for, on the frame it is asked for.
struct HoldProgressBar: View {
    let since: Date
    let duration: TimeInterval
    var width: CGFloat = 180

    var body: some View {
        TimelineView(.animation) { context in
            Bar(progress: progress(at: context.date), width: width, tint: .accentColor)
        }
    }

    private func progress(at date: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(since) / duration))
    }
}

/// The filled, completed counterpart shown once a gesture has fired, so the
/// hold reads as finished rather than simply vanishing.
struct CompletedHoldBar: View {
    var width: CGFloat = 180

    var body: some View {
        Bar(progress: 1, width: width, tint: .green)
    }
}

/// Track plus fill, drawn as plain shapes so no view-backed smoothing sits
/// between the computed progress and what lands on screen.
private struct Bar: View {
    var progress: Double
    var width: CGFloat
    var tint: Color

    private let height: CGFloat = 6

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .overlay(alignment: .leading) {
                // A rectangle clipped to the capsule keeps the fill's leading
                // end rounded without the shape distorting at low progress.
                Rectangle()
                    .fill(tint)
                    .frame(width: max(0, min(width, width * progress)))
            }
            .clipShape(Capsule())
            .frame(width: width, height: height)
            // The value is already recomputed every frame; interpolating on
            // top of that is what reintroduces the trailing.
            .animation(nil, value: progress)
    }
}
