import SwiftUI

/// The small per-habit indicator shown on every HealthKit-tracked habit's
/// card/row (§4) — one shared component so there's exactly one place that
/// decides what this badge looks like, used at all four render sites
/// (`CategoryDetailView`'s template picker, `HomeView`'s habit cards,
/// `ProgressScreenView`'s habit list, `HabitDetailView`'s header).
///
/// **This is deliberately not Apple's real "Works with Apple Health"
/// trademark badge — a considered decision, not a placeholder-by-neglect.**
/// Investigated this pass: that badge is real, downloadable from
/// developer.apple.com/health-fitness/, and comes with an explicit
/// "Developer Artwork License Agreement for Works with Apple Health" a
/// logged-in Apple Developer Program member must read and agree to before
/// use — not something obtainable or agreeable-to programmatically on the
/// app owner's behalf, so it isn't bundled here. Separately, and just as
/// importantly: that badge's own guidelines describe it for **marketing**
/// contexts specifically (App Store listing/description, the app's own
/// website, ads, email) — "communicate your app's compatibility," "one
/// badge per promotion" — not as a small repeated indicator glyph on every
/// individual habit row throughout the app's day-to-day UI, which isn't
/// among its approved usage contexts at all. Using the real trademarked
/// asset in that role would be stretching it well past what its own
/// guidelines describe, independent of the licensing question.
///
/// If the app owner wants the real badge on marketing surfaces (App Store
/// screenshots, a marketing website) that's a separate, one-time asset
/// question outside this codebase's UI layer — not this component's job.
/// This component's job is a lightweight, always-available, license-free
/// in-app indicator: a heart glyph, filled+pink when connected (the same
/// color already used for `MilestoneKind`'s HealthKit-adjacent accents),
/// outlined+secondary when the habit is HealthKit-tracked but not
/// currently connected.
struct HealthKitBadgeView: View {
    /// `nil` when connection status isn't relevant/known at this call site
    /// (e.g. the template picker, before any habit even exists yet) — shows
    /// the plain filled-pink "this is HealthKit-tracked" mark with no
    /// connected/disconnected distinction.
    var isConnected: Bool?

    var body: some View {
        switch isConnected {
        case .some(true), .none:
            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)
        case .some(false):
            Image(systemName: "heart.slash")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        HealthKitBadgeView()
        HealthKitBadgeView(isConnected: true)
        HealthKitBadgeView(isConnected: false)
    }
    .font(.title2)
    .padding()
}
