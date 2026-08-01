import Foundation
import CoreLocation

/// Foreground, one-shot location for prayer-time calculation (P1 Phase 2).
/// Privacy-conscious per the spec: **when-in-use** authorization only (never
/// "always"/background), a single `requestLocation()` fix rather than
/// continuous tracking, and city-level accuracy (`kCLLocationAccuracyThree
/// Kilometers`) — more than precise enough for prayer times and it avoids the
/// precise-location prompt/battery cost. The last-known coordinate is
/// persisted so prayer times still compute offline / before a fresh fix
/// arrives (a prayer schedule that's a few km stale is still correct to the
/// minute).
///
/// `@MainActor @Observable` for SwiftUI binding; the `CLLocationManagerDelegate`
/// callbacks arrive on a nonisolated context and hop to the main actor with
/// only `Sendable` values (never the non-`Sendable` `CLLocationManager`).
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private static let defaultsKey = "forge.prayer.lastKnownCoordinate"

    /// Most recent (or persisted last-known) location. `nil` until the user
    /// grants access and a first fix lands.
    private(set) var coordinate: Coordinate?
    private(set) var authorizationStatus: CLAuthorizationStatus

    override init() {
        authorizationStatus = manager.authorizationStatus
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Coordinate.self, from: data) {
            coordinate = saved
        }
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    /// Prompt for when-in-use access (a no-op if already decided). On grant,
    /// `locationManagerDidChangeAuthorization` fires a one-shot fix.
    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Request a single location fix (requires authorization already granted).
    func requestLocation() {
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate (nonisolated → hop with Sendable only)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        Task { @MainActor in self.store(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Intentionally keep the last-known coordinate — a transient failure
        // shouldn't wipe a usable location; prayer times still compute from
        // whatever was persisted.
    }

    private func store(_ coordinate: Coordinate) {
        self.coordinate = coordinate
        if let data = try? JSONEncoder().encode(coordinate) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
