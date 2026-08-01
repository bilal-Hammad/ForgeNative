import Foundation

/// A plain latitude/longitude pair — Adhan-free and `Codable`, so a
/// last-known location can be persisted (`LocationService`) and passed into
/// `PrayerTimeService` without leaking CoreLocation's `CLLocationCoordinate2D`
/// or Adhan's `Coordinates` across the app. `PrayerTimeService` is the only
/// place that converts this into Adhan's own type.
struct Coordinate: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}
