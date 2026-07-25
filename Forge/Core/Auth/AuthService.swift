import AuthenticationServices
import Foundation

/// The real-identity boundary APP_REDESIGN_SPEC.md §9 requires before
/// friends/per-habit competition can be built ("you can't have 'friends'
/// without real user identity"). This pass builds the auth capability
/// itself in isolation — real Sign in with Apple, a persisted identity,
/// credential-revocation detection — deliberately with no backend/friends
/// wiring yet, since neither exists in this codebase (confirmed: zero
/// Supabase/CloudKit consuming code in `Forge/` as of this pass — see
/// TASKS.md's P2 "Compete-with-friends" entry). Future phases plug a real
/// backend identity behind this same boundary; `ProfileView` is the only
/// consumer today.
///
/// `handleSignIn` takes plain `Sendable` fields rather than the
/// `ASAuthorizationAppleIDCredential` itself — that type isn't `Sendable`,
/// and Swift 6's strict concurrency (this project's `SWIFT_VERSION`)
/// would reject passing it across the actor boundary below. Callers
/// extract `credential.user`/`.email`/`.fullName` on the main thread
/// (where `SignInWithAppleButton`'s `onCompletion` already runs) before
/// calling in.
protocol AuthService: Sendable {
    /// Restores the persisted session, if any, and validates it against
    /// Apple's own credential state (per Apple's HIG: check this at every
    /// app launch — a user can revoke Sign in with Apple for this app from
    /// Settings without the app being told directly). Returns `nil` and
    /// clears local state if the credential is no longer valid.
    func restoreSession() async -> AuthUser?
    func handleSignIn(userID: String, email: String?, fullName: String?) async -> AuthUser
    func signOut() async
}

actor AppleAuthService: AuthService {
    func restoreSession() async -> AuthUser? {
        guard let data = KeychainStore.load(),
              let user = try? JSONDecoder().decode(AuthUser.self, from: data) else {
            return nil
        }
        switch await credentialState(forUserID: user.id) {
        case .authorized:
            return user
        case .revoked, .notFound, .transferred:
            KeychainStore.clear()
            return nil
        @unknown default:
            return user
        }
    }

    func handleSignIn(userID: String, email: String?, fullName: String?) async -> AuthUser {
        // Apple only returns email/fullName on this app's very first
        // authorization for this Apple ID — later sign-ins return `nil`
        // for both, so merge with whatever was already persisted (e.g. a
        // previously-signed-in, then-locally-signed-out user
        // re-authenticating) instead of losing it.
        let previous = KeychainStore.load().flatMap { try? JSONDecoder().decode(AuthUser.self, from: $0) }
        let user = AuthUser(
            id: userID,
            email: email ?? previous?.email,
            fullName: fullName ?? previous?.fullName
        )
        if let data = try? JSONEncoder().encode(user) {
            KeychainStore.save(data)
        }
        return user
    }

    func signOut() async {
        KeychainStore.clear()
    }

    private func credentialState(forUserID userID: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }
}

/// Always-signed-out stand-in for previews/tests — mirrors
/// `StubEntitlementService`'s role for `EntitlementService`. No real
/// Sign in with Apple flow should ever run in a preview or in
/// `-uiTesting` mode.
struct InMemoryAuthService: AuthService {
    func restoreSession() async -> AuthUser? { nil }
    func handleSignIn(userID: String, email: String?, fullName: String?) async -> AuthUser {
        AuthUser(id: userID, email: email, fullName: fullName)
    }
    func signOut() async {}
}
