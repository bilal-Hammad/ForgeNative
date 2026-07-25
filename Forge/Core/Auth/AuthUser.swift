import Foundation

/// A signed-in Apple ID identity — `id` is Apple's stable, opaque per-app
/// user identifier (`ASAuthorizationAppleIDCredential.user`), not a general
/// backend user ID (there's no backend yet — see `AuthService`'s doc
/// comment). `email`/`fullName` are optional because Apple only ever
/// returns them on a user's very first Sign in with Apple for this app —
/// every later sign-in returns `nil` for both, so both must be persisted
/// locally the first time they're seen (`AppleAuthService` handles this).
struct AuthUser: Codable, Equatable, Sendable {
    let id: String
    let email: String?
    let fullName: String?

    var displayName: String {
        fullName ?? email ?? "Forge User"
    }
}
