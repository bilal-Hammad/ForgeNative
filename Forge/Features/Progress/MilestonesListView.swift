import SwiftUI

/// Full Milestones list (APP_REDESIGN_SPEC.md §11), reached by tapping
/// Progress's Milestones card. Grouped the same way Apple's own Awards
/// screen groups by kind, adapted to Forge's three real kinds rather than
/// Apple's exact categories: Streak Milestones (habit + category streaks
/// together), Category Challenges, Points Milestones.
struct MilestonesListView: View {
    @Environment(\.milestoneRepository) private var milestoneRepository
    @Environment(\.milestoneEngine) private var milestoneEngine
    @State private var milestones: [Milestone] = []

    private var streakMilestones: [Milestone] {
        milestones.filter { $0.kind == .habitStreak || $0.kind == .categoryStreak }
            .sorted { $0.earnedDate > $1.earnedDate }
    }

    private var categoryChallenges: [Milestone] {
        milestones.filter { $0.kind == .categoryChallenge }.sorted { $0.earnedDate > $1.earnedDate }
    }

    private var pointsMilestones: [Milestone] {
        milestones.filter { $0.kind == .points }.sorted { $0.earnedDate > $1.earnedDate }
    }

    var body: some View {
        List {
            if !streakMilestones.isEmpty {
                Section("Streak Milestones") {
                    ForEach(streakMilestones) { milestone in
                        NavigationLink {
                            MilestoneDetailView(milestone: milestone)
                        } label: {
                            MilestoneRow(milestone: milestone)
                        }
                    }
                }
            }
            if !categoryChallenges.isEmpty {
                Section("Category Challenges") {
                    ForEach(categoryChallenges) { milestone in
                        NavigationLink {
                            MilestoneDetailView(milestone: milestone)
                        } label: {
                            MilestoneRow(milestone: milestone)
                        }
                    }
                }
            }
            if !pointsMilestones.isEmpty {
                Section("Points Milestones") {
                    ForEach(pointsMilestones) { milestone in
                        NavigationLink {
                            MilestoneDetailView(milestone: milestone)
                        } label: {
                            MilestoneRow(milestone: milestone)
                        }
                    }
                }
            }
            if milestones.isEmpty {
                ContentUnavailableView(
                    "No Milestones Yet",
                    systemImage: "seal",
                    description: Text("Build streaks and hit points thresholds to start earning badges.")
                )
            }
        }
        .navigationTitle("Milestones")
        .task {
            await milestoneEngine.runCatchUp()
            milestones = (try? await milestoneRepository.fetchAll()) ?? []
        }
    }
}

private struct MilestoneRow: View {
    let milestone: Milestone

    var body: some View {
        HStack(spacing: 14) {
            MilestoneBadgePreview(color: milestone.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.title)
                    .font(.body.weight(.semibold))
                Text(milestone.earnedDate, format: .dateTime.month(.wide).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        MilestonesListView()
            .environment(\.milestoneRepository, InMemoryMilestoneRepository())
    }
}
