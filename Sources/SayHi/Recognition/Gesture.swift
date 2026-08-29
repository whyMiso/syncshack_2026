import Foundation

/// The gestures SayHi can recognise. Add new cases here and teach
/// `GestureClassifier` how to detect them; everything else (mapping UI,
/// persistence, state machine) picks new cases up automatically.
enum Gesture: String, Codable, CaseIterable, Identifiable, Hashable {
    case fist
    case openPalm
    case thumbsUp
    case peace
    case pointUp
    case thumbsDown
    case ok
    case rock
    case callMe
    case three
    case pointDown
    case pointLeft
    case pointRight
    case unknown

    var id: String { rawValue }

    /// Gestures the user can assign actions to (everything except `.unknown`).
    static var assignable: [Gesture] {
        allCases.filter { $0 != .unknown }
    }

    var displayName: String {
        switch self {
        case .fist:       return "Closed Fist"
        case .openPalm:   return "Open Palm"
        case .thumbsUp:   return "Thumbs Up"
        case .peace:      return "Peace Sign"
        case .pointUp:    return "Point Up"
        case .thumbsDown: return "Thumbs Down"
        case .ok:         return "OK Sign"
        case .rock:       return "Rock Sign"
        case .callMe:     return "Call Me"
        case .three:      return "Three Fingers"
        case .pointDown:  return "Point Down"
        case .pointLeft:  return "Point Left"
        case .pointRight: return "Point Right"
        case .unknown:    return "—"
        }
    }

    /// The emoji shown as the gesture's mark. `GestureGlyph` renders it
    /// desaturated so only the shape survives — see that file.
    var symbol: String {
        switch self {
        case .fist:       return "✊"
        case .openPalm:   return "🖐️"
        case .thumbsUp:   return "👍"
        case .peace:      return "✌️"
        case .pointUp:    return "☝️"
        case .thumbsDown: return "👎"
        case .ok:         return "👌"
        case .rock:       return "🤘"
        case .callMe:     return "🤙"
        case .three:      return "3️⃣"
        case .pointDown:  return "👇"
        case .pointLeft:  return "👈"
        case .pointRight: return "👉"
        case .unknown:    return "·"
        }
    }
}

/// Which hand performed a gesture. Left and right are separate binding keys,
/// so every gesture can drive two different actions.
enum HandSide: String, Codable, CaseIterable, Identifiable, Hashable {
    case left
    case right

    var id: String { rawValue }

    var displayName: String { self == .left ? "Left Hand" : "Right Hand" }
    var shortName: String { self == .left ? "Left" : "Right" }
}

/// A (gesture, hand) pair — the key an action is bound to.
struct GestureBinding: Hashable, Codable, Identifiable {
    var gesture: Gesture
    var hand: HandSide

    /// Stable string form, used as the JSON key in the mappings file.
    var id: String { "\(gesture.rawValue).\(hand.rawValue)" }

    /// "Closed Fist (left hand)" — naming the hand after the gesture keeps it
    /// unambiguous for gestures whose own name contains a direction.
    var displayName: String { "\(gesture.displayName) (\(hand.shortName.lowercased()) hand)" }

    init(gesture: Gesture, hand: HandSide) {
        self.gesture = gesture
        self.hand = hand
    }

    /// Reverse of `id`, for reading the mappings file.
    init?(id: String) {
        let parts = id.split(separator: ".")
        guard parts.count == 2,
              let gesture = Gesture(rawValue: String(parts[0])),
              let hand = HandSide(rawValue: String(parts[1])) else { return nil }
        self.init(gesture: gesture, hand: hand)
    }
}

/// A classification result: what the classifier thinks it sees and how sure it is.
struct GestureReading: Equatable {
    var gesture: Gesture
    var confidence: Double  // 0...1

    static let none = GestureReading(gesture: .unknown, confidence: 0)
}
