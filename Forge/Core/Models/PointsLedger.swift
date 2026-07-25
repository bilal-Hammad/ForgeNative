import Foundation

/// Running §8 points total, evaluated day-by-day rather than recomputed
/// from scratch — `lastEvaluatedDay` marks the most recent calendar day
/// whose point delta has already been folded into `cumulativePoints`, so a
/// catch-up run only ever has to process days after it (normally zero, at
/// most a handful) instead of the habit's entire history every time.
struct PointsLedger: Codable, Equatable {
    var cumulativePoints: Int
    var lastEvaluatedDay: Date?

    static let empty = PointsLedger(cumulativePoints: 0, lastEvaluatedDay: nil)
}
