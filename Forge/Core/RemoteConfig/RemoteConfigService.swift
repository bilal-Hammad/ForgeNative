import Foundation

/// Fetches + caches the remote marketing `RemoteConfig` (P1 Phase 8).
/// **Never blocks the paywall**: the last-cached (or built-in fallback) config
/// is available synchronously the instant this is created; `refresh()` updates
/// it in the background and any failure silently keeps the cached/fallback
/// value. Purchase/transaction logic is never touched here — this is marketing
/// data only.
///
/// **Hosting is deliberately unresolved (flagged for Bilal):** `remoteURL` is
/// `nil` by default, so `refresh()` is a no-op and the app runs entirely on
/// the built-in fallback until a hosting location is chosen. Set `remoteURL`
/// to a static HTTPS JSON endpoint (a CDN object, GitHub raw file, S3, etc.)
/// when that small decision is made — no other code changes needed. Because
/// the payload is public, read-only marketing copy with no secrets and no
/// charged prices (see `RemoteConfig`), plain HTTPS with a fallback is
/// sufficient; there's no auth/signing to design.
@MainActor
@Observable
final class RemoteConfigService {
    private(set) var config: RemoteConfig
    private let remoteURL: URL?
    private let cacheKey = "forge.remoteConfig.cache.v1"

    init(remoteURL: URL? = RemoteConfigService.defaultRemoteURL) {
        self.remoteURL = remoteURL
        // Cached value if present, else the built-in fallback — synchronous,
        // so the paywall always has something usable immediately.
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(RemoteConfig.self, from: data) {
            config = cached
        } else {
            config = .fallback
        }
    }

    /// Best-effort background refresh. Any failure (no URL, offline, bad JSON)
    /// silently keeps the current config — it must never surface an error to
    /// or block the paywall.
    func refresh() async {
        guard let remoteURL else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let fetched = try JSONDecoder().decode(RemoteConfig.self, from: data)
            config = fetched
            UserDefaults.standard.set(data, forKey: cacheKey)
        } catch {
            // Intentionally ignored — keep cached/fallback.
        }
    }

    /// TBD hosting decision (flagged): set to the static config URL once chosen.
    /// `nil` → the app runs on the built-in fallback (fully functional).
    nonisolated static let defaultRemoteURL: URL? = nil
}
