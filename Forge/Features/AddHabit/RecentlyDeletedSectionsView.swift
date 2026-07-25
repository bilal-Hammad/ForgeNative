import SwiftUI

/// "Recently Deleted" — soft-deleted sections with a Restore action, per
/// Apple Reminders' own equivalent. Deleting a section from
/// `EditSectionsView` lands here first rather than being destroyed outright.
struct RecentlyDeletedSectionsView: View {
    let category: HabitCategory
    var onChange: () -> Void

    @Environment(\.templateSectionRepository) private var repository
    @State private var deletedSections: [TemplateSection] = []

    var body: some View {
        List {
            if deletedSections.isEmpty {
                Text("No recently deleted sections.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(deletedSections) { section in
                    HStack {
                        Text(section.displayName)
                        Spacer()
                        Button("Restore") {
                            Task { await restore(section) }
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func reload() async {
        guard let config = try? await repository.fetchConfiguration(for: category) else { return }
        deletedSections = config.resolvedDeletedSections(for: category)
    }

    private func restore(_ section: TemplateSection) async {
        try? await repository.restore(sectionID: section.id, for: category)
        await reload()
        onChange()
    }
}

#Preview {
    NavigationStack {
        RecentlyDeletedSectionsView(category: .good, onChange: {})
    }
    .environment(\.templateSectionRepository, InMemoryTemplateSectionRepository())
}
