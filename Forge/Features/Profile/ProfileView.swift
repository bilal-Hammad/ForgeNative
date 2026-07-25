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
/// Sign-in state: real Apple Sign-In/backend doesn't exist in ForgeNative yet
/// (§10-adjacent "sensitive integration," deferred). `isSignedIn` is
/// hardcoded false — the signed-in branch (photo + name instead of the
/// generic silhouette) is built for when that lands, but is unreachable and
/// untested today since the Sign-in button is a disabled stub.
struct ProfileView: View {
    @State private var isSignedIn = false
    @State private var scrollOffset: CGFloat = 0

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

                    Spacer(minLength: 400)
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
                        if isSignedIn {
                            Text("Forge User")
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
        }
    }

    private var largeHeader: some View {
        VStack(spacing: 12) {
            avatar(size: 96)

            if isSignedIn {
                Text("Forge User")
                    .font(.title2.weight(.semibold))
            } else {
                Text("Not Signed In")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)

                Button {
                    // Stub — no auth/backend layer in ForgeNative yet.
                } label: {
                    Label("Sign in with Apple", systemImage: "apple.logo")
                }
                .disabled(true)
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
}
