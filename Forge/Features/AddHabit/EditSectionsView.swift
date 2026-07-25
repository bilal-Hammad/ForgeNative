import SwiftUI

/// Section-editing screen for one category's sections (Good/Bad/To-Do
/// themselves are fixed — this only edits the sections inside one of them,
/// e.g. Health & Fitness/Mindfulness/etc. inside Good), styled directly after
/// Apple Reminders' own "Edit Lists" screen.
///
/// The red minus-circle (delete) and drag handle (reorder) are the REAL
/// native `List` edit-mode UI — forcing `.editMode` permanently active with
/// `.onDelete`/`.onMove` gives the exact same UIKit-backed interaction
/// Reminders itself uses, rather than hand-rolled buttons approximating it.
/// The info "i" button is added per-row as ordinary row content alongside
/// that native chrome.
///
/// "Reset to default" lives one level up now, in `CategoryDetailView`'s own
/// "•••" menu as a sibling to "Edit" (APP_REDESIGN_SPEC.md §5) — it used to
/// be a toolbar button on this screen, nested one level deeper than the
/// spec describes; moved up rather than duplicated in both places.
struct EditSectionsView: View {
    let category: HabitCategory
    var onChange: () -> Void

    @Environment(\.templateSectionRepository) private var repository
    @State private var sections: [TemplateSection] = []
    @State private var deletedCount = 0
    @State private var isPresentingAddSection = false
    @State private var editingCustomSection: TemplateSection?

    var body: some View {
        List {
            Section {
                ForEach(sections) { section in
                    HStack {
                        Text(section.displayName)
                        if section.tier == .premium {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            editingCustomSection = section
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete { offsets in
                    Task { await delete(at: offsets) }
                }
                .onMove { source, destination in
                    sections.move(fromOffsets: source, toOffset: destination)
                    Task { await persistOrder() }
                }
            }

            Section {
                NavigationLink {
                    RecentlyDeletedSectionsView(category: category) {
                        Task { await reload() }
                        onChange()
                    }
                } label: {
                    HStack {
                        Text("Recently Deleted")
                        Spacer()
                        if deletedCount > 0 {
                            Text("\(deletedCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    isPresentingAddSection = true
                } label: {
                    Label("Add Section", systemImage: "plus.circle.fill")
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Edit \(category.displayName) Sections")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingAddSection) {
            AddSectionView(category: category) {
                isPresentingAddSection = false
                Task { await reload() }
                onChange()
            }
        }
        .sheet(item: $editingCustomSection) { section in
            EditSectionDetailView(section: section) {
                editingCustomSection = nil
                Task { await reload() }
                onChange()
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        guard let config = try? await repository.fetchConfiguration(for: category) else { return }
        sections = config.resolvedActiveSections(for: category)
        deletedCount = config.deletedSectionIDs.count
    }

    private func persistOrder() async {
        try? await repository.setActiveSectionOrder(sections.map(\.id), for: category)
        onChange()
    }

    private func delete(at offsets: IndexSet) async {
        for index in offsets {
            try? await repository.softDelete(sectionID: sections[index].id, for: category)
        }
        await reload()
        onChange()
    }
}

#Preview {
    NavigationStack {
        EditSectionsView(category: .good, onChange: {})
    }
    .environment(\.templateSectionRepository, InMemoryTemplateSectionRepository())
}
