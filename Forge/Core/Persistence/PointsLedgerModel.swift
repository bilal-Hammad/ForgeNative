import Foundation
import SwiftData

/// Singleton row (`singletonKey` is always `"ledger"` and unique, so SwiftData
/// itself enforces there's ever only one) holding the running §8 points
/// total and the catch-up watermark described on `PointsLedger`.
@Model
final class PointsLedgerModel {
    @Attribute(.unique) var singletonKey: String
    var cumulativePoints: Int
    var lastEvaluatedDay: Date?

    init(cumulativePoints: Int, lastEvaluatedDay: Date?) {
        self.singletonKey = "ledger"
        self.cumulativePoints = cumulativePoints
        self.lastEvaluatedDay = lastEvaluatedDay
    }
}

extension PointsLedgerModel {
    func toLedger() -> PointsLedger {
        PointsLedger(cumulativePoints: cumulativePoints, lastEvaluatedDay: lastEvaluatedDay)
    }

    func update(from ledger: PointsLedger) {
        cumulativePoints = ledger.cumulativePoints
        lastEvaluatedDay = ledger.lastEvaluatedDay
    }
}
