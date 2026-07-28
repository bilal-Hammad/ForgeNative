import SwiftUI

private struct CalendarSyncServiceKey: EnvironmentKey {
    static let defaultValue: CalendarSyncService = NoOpCalendarSyncService()
}

extension EnvironmentValues {
    var calendarSyncService: CalendarSyncService {
        get { self[CalendarSyncServiceKey.self] }
        set { self[CalendarSyncServiceKey.self] = newValue }
    }
}
