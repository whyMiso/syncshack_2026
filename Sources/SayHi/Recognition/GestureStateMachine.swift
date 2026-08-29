import Foundation

/// Turns a noisy per-frame stream of gesture readings into deliberate,
/// single-shot trigger events.
///
/// The unit tracked is a `GestureBinding` — gesture *and* hand — so a left
/// fist and a right fist are different things: switching hands mid-hold
/// restarts the timer rather than counting toward the wrong action.
///
/// Rules enforced:
///  1. A binding must be held continuously for `holdDuration` before firing.
///  2. Brief dropouts (< `dropoutGrace`) don't reset the hold — Vision
///     occasionally misses a frame even on a steady hand.
///  3. After firing, everything is locked out for `cooldown`.
///  4. After cooldown, the binding that fired must *disappear* for
///     `rearmDuration` (hand relaxed or changed) before it can fire again —
///     holding a fist forever produces exactly one screenshot.
struct GestureStateMachine {

    enum Phase: Equatable {
        case idle
        /// Building up toward a trigger.
        case holding(GestureBinding, since: Date)
        /// Just fired `fired`; ignoring everything until `until`.
        case cooldown(fired: GestureBinding, until: Date)
        /// Cooldown elapsed but the fired binding may still be on screen;
        /// it must be absent for `rearmDuration` before it can fire again.
        case awaitingRearm(GestureBinding)
    }

    struct Snapshot {
        var phase: Phase
        /// 0...1 progress toward triggering, for the "Hold gesture…" UI.
        var holdProgress: Double
        var consecutiveFrames: Int
        var isArmed: Bool

        /// The binding currently being held, if any.
        var holding: GestureBinding? {
            if case .holding(let binding, _) = phase { return binding }
            return nil
        }
    }

    private(set) var phase: Phase = .idle
    private var consecutiveFrames = 0
    /// Last moment the currently-held binding was actually seen (dropout grace).
    private var lastSeenHeldBinding = Date.distantPast
    /// How long the rearm-blocked binding has been absent.
    private var absentSince: Date?

    private var config: GestureConfig { GestureConfig.shared }

    /// Feed one frame's binding (`nil` when no gesture is recognised).
    /// Returns a binding exactly when it should trigger.
    mutating func process(_ binding: GestureBinding?, at now: Date = Date()) -> GestureBinding? {
        switch phase {
        case .cooldown(let fired, let until):
            guard now >= until else { return nil }
            phase = .awaitingRearm(fired)
            absentSince = nil
            return process(binding, at: now)

        case .awaitingRearm(let blocked):
            if binding == blocked {
                absentSince = nil  // still showing it; stay blocked
                return nil
            }
            if absentSince == nil { absentSince = now }
            guard now.timeIntervalSince(absentSince!) >= config.rearmDuration else {
                return nil
            }
            phase = .idle
            absentSince = nil
            return process(binding, at: now)

        case .idle:
            if let binding {
                phase = .holding(binding, since: now)
                consecutiveFrames = 1
                lastSeenHeldBinding = now
            }
            return nil

        case .holding(let held, let since):
            if binding == held {
                consecutiveFrames += 1
                lastSeenHeldBinding = now
                if now.timeIntervalSince(since) >= config.holdDuration {
                    phase = .cooldown(fired: held, until: now.addingTimeInterval(config.cooldown))
                    consecutiveFrames = 0
                    return held
                }
            } else if binding == nil {
                // Tolerate brief dropouts; reset only if the hand is really gone.
                if now.timeIntervalSince(lastSeenHeldBinding) > config.dropoutGrace {
                    phase = .idle
                    consecutiveFrames = 0
                }
            } else {
                // A different gesture *or the other hand*: start that hold instead.
                phase = .holding(binding!, since: now)
                consecutiveFrames = 1
                lastSeenHeldBinding = now
            }
            return nil
        }
    }

    func snapshot(at now: Date = Date()) -> Snapshot {
        let progress: Double
        switch phase {
        case .holding(_, let since):
            progress = min(1, now.timeIntervalSince(since) / config.holdDuration)
        default:
            progress = 0
        }
        let armed: Bool
        switch phase {
        case .cooldown, .awaitingRearm: armed = false
        default: armed = true
        }
        return Snapshot(phase: phase,
                        holdProgress: progress,
                        consecutiveFrames: consecutiveFrames,
                        isArmed: armed)
    }

    mutating func reset() {
        phase = .idle
        consecutiveFrames = 0
        absentSince = nil
    }
}
