import SwiftUI

/// Badge detail page — the one place `Badge3DView`'s real tilt-responsive
/// SceneKit render actually shows (see that type's doc comment for why it's
/// reserved for a single-instance context, not list rows).
///
/// Copy is original wording, not Apple's "Earned by [Name] in [Month Year]"
/// phrasing — and skips the "[Name]" personalization entirely rather than
/// guessing at one: Forge has no real signed-in user identity yet (Apple
/// Sign In on Profile is still a disabled stub with no stored display name),
/// so "Earned by ___" would have nothing honest to fill in.
struct MilestoneDetailView: View {
    let milestone: Milestone

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Badge3DView(color: milestone.color)
                    .frame(width: 220, height: 220)
                    .padding(.top, 16)

                VStack(spacing: 6) {
                    Text(milestone.title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Earned \(milestone.earnedDate.formatted(.dateTime.month(.wide).day().year()))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(milestone.subtitle)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        MilestoneDetailView(
            milestone: Milestone(
                kind: .habitStreak,
                scopeID: UUID().uuidString,
                value: 30,
                title: "30-Day Streak",
                subtitle: "Read completed 30 days in a row.",
                earnedDate: .now,
                colorToken: "blue"
            )
        )
    }
}
