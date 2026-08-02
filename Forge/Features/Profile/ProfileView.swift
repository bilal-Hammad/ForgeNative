import AuthenticationServices
import SwiftUI

/// Profile screen. No "Profile" nav title — the large photo+name header is
/// the page's main element (Apple Health Summary-tab reference), and it
/// collapses into a small circular avatar in the nav bar as the user scrolls,
/// matching Music/App Store/Health's own profile-tab pattern.
///
/// Mechanism (real, researched — not a rough approximation): SwiftUI's
/// `.onScrollGeometryChange(for:of:action:)` (iOS 18+) reports the
/// `ScrollView`'s live `contentOffset`, which drives two independently
/// crossfading elements — the large header shrinks (`scaleEffect`) and fades
/// (`opacity`) as it scrolls up, while a small avatar+name in the toolbar's
/// `.principal` item fades in at the same rate. This is genuinely how Apple's
/// own apps achieve the effect: not one element flying via matched geometry
/// across the ScrollView/toolbar boundary (SwiftUI doesn't support matched
/// geometry across that boundary), but two elements crossfading in lockstep,
/// which reads as one continuous transition.
///
/// Sign-in state: real Sign in with Apple now works (`AuthService` —
/// APP_REDESIGN_SPEC.md §9's hard prerequisite for friends/competition,
/// built in isolation ahead of that feature since neither a backend nor
/// friends exist yet in this codebase). No name/photo beyond what Apple
/// hands back (`AuthUser.displayName`) — there's still no backend profile
/// to fetch a real avatar from, so the generic silhouette stays even when
/// signed in.
struct ProfileView: View {
    @Environment(\.authService) private var authService
    @Environment(\.entitlementService) private var entitlementService
    @State private var currentUser: AuthUser?
    @State private var scrollOffset: CGFloat = 0
    /// The general subscribe entry point (P1 Phase 8 wiring gap fixed 2026-08-02):
    /// PaywallView was only reachable via the deep Add-Section flow. This card
    /// opens the generic (subscription) paywall directly from Profile.
    @State private var isPremium = false
    @State private var showingPaywall = false

    private var isSignedIn: Bool { currentUser != nil }

    private let collapseThreshold: CGFloat = 60

    private var collapseProgress: CGFloat {
        min(max(scrollOffset / collapseThreshold, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    largeHeader
                        .opacity(1 - collapseProgress)
                        .scaleEffect(1 - 0.3 * collapseProgress, anchor: .top)
                        .padding(.top, 12)

                    premiumCard
                        .padding(.horizontal)

                    Spacer(minLength: 300)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                scrollOffset = newValue
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        avatar(size: 26)
                        if let currentUser {
                            Text(currentUser.displayName)
                                .font(.headline)
                        }
                    }
                    .opacity(collapseProgress)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .task {
                currentUser = await authService.restoreSession()
                isPremium = await entitlementService.isPremiumUnlocked()
            }
            .sheet(isPresented: $showingPaywall, onDismiss: {
                Task { isPremium = await entitlementService.isPremiumUnlocked() }
            }) {
                PaywallView()
            }
        }
    }

    /// "Forge Premium" card — the general subscribe entry point. Shows an
    /// active state once premium is unlocked, otherwise a tappable upgrade
    /// button that opens the (subscription) paywall.
    @ViewBuilder
    private var premiumCard: some View {
        if isPremium {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill").foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Forge Premium").font(.headline)
                    Text("Active — all features and packs unlocked")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        } else {
            Button {
                showingPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill").foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upgrade to Forge Premium").font(.headline)
                        Text("Unlock every feature and template pack")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.upgradeToPremium")
        }
    }

    private var largeHeader: some View {
        VStack(spacing: 12) {
            avatar(size: 96)

            if let currentUser {
                Text(currentUser.displayName)
                    .font(.title2.weight(.semibold))

                Button("Sign Out") {
                    Task {
                        await authService.signOut()
                        self.currentUser = nil
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            } else {
                Text("Not Signed In")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    guard case .success(let authorization) = result,
                          let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                        return
                    }
                    // Extracted here, on the main thread this closure
                    // already runs on, since `ASAuthorizationAppleIDCredential`
                    // itself isn't `Sendable` — see `AuthService`'s doc
                    // comment for why the actor boundary takes plain
                    // fields instead of the credential object.
                    let userID = credential.user
                    let email = credential.email
                    let fullName = credential.fullName.flatMap { components -> String? in
                        let name = PersonNameComponentsFormatter().string(from: components)
                        return name.isEmpty ? nil : name
                    }
                    Task {
                        currentUser = await authService.handleSignIn(userID: userID, email: email, fullName: fullName)
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(width: 220, height: 44)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func avatar(size: CGFloat) -> some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    ProfileView()
        .environment(\.habitRepository, InMemoryHabitRepository())
        .environment(\.authService, InMemoryAuthService())
}
