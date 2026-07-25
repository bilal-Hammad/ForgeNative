import SwiftUI

/// APP_REDESIGN_SPEC.md §13's daily mood check-in scale: a discrete 5-point
/// pick, not a continuous slider — deliberately different from Apple
/// Health's "State of Mind" feature (a continuous slider across a purple/
/// blue/orange spectrum, plus a follow-up adjective-word chip picker), to
/// stay a visually distinct design rather than a copy, same principle
/// already applied to the Home strip (`RingsView` → flat bars) and
/// Milestones (§11's own shape/material departures from Apple Fitness).
///
/// **Visual identity, chosen this pass (flagged as a judgment call — the
/// spec names the 5-point scale itself but not its exact colors/icons):**
/// a five-stop green→red scale reusing colors already meaningful elsewhere
/// in this app (`HabitCategory.good` is green, `.bad` is red) rather than
/// Apple's purple/blue/orange spectrum, paired with a weather-metaphor SF
/// Symbol per level (sun → storm) instead of face/emoji glyphs — SF Symbols
/// are this app's existing icon language (every `Habit` already carries an
/// `iconSystemName`), but a *weather* metaphor specifically (rather than
/// literal face icons) keeps this from reading as "just an emoji mood
/// picker," which is the generic pattern most competing habit apps already
/// use, and also sidesteps Apple's own face-based Memoji/adjective-chip
/// design entirely.
enum MoodLevel: String, Codable, CaseIterable, Identifiable {
    case great, good, okay, low, rough

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .great: "Great"
        case .good: "Good"
        case .okay: "Okay"
        case .low: "Low"
        case .rough: "Rough"
        }
    }

    var systemImage: String {
        switch self {
        case .great: "sun.max.fill"
        case .good: "cloud.sun.fill"
        case .okay: "cloud.fill"
        case .low: "cloud.drizzle.fill"
        case .rough: "cloud.bolt.rain.fill"
        }
    }

    var color: Color {
        switch self {
        case .great: .green
        case .good: .mint
        case .okay: .gray
        case .low: .orange
        case .rough: .red
        }
    }

    /// Numeric axis (great=5 … rough=1), purely for the future correlation
    /// feature (§13: "days you completed your Good habits tend to have
    /// higher mood ratings") — not used for anything scored/gamified today.
    /// Mood is deliberately kept out of `PointsLedger`/streak math entirely
    /// (§13: "recommend: no — keep mood purely observational/reflective").
    var scoreValue: Int {
        switch self {
        case .rough: 1
        case .low: 2
        case .okay: 3
        case .good: 4
        case .great: 5
        }
    }
}
