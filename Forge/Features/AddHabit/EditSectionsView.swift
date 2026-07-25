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
struct EditSectionsView: View {
    let category: HabitCategory
    var onChange: () -> Void

    @Environment(\.templateSectionRepository) private var repository
    @State private var sections: [TemplateSection] = []
    @State private var deletedCount = 0
    @State private var isPresentingAddSection = false
    @State private var editingCustomSection: TemplateSection?
    @State private var isPresentingResetConfirm = false

    /// Whether the current section state actually differs from default —
    /// drives Reset's color so it only reads as destructive when it would
    /// actually change something. Only the built-in portion of `sections`
    /// counts: a custom section's mere presence isn't something Reset would
    /// undo (it preserves custom sections), so it shouldn't make Reset look
    /// destructive on its own.
    private var isModifiedFromDefault: Bool {
        let builtInIDs = TemplateCatalog.sections(for: category).map(\.id)
        let currentBuiltInOrder = sections.map(\.id).filter(builtInIDs.contains)
        return currentBuiltInOrder != TemplateCatalog.defaultSectionIDs(for: category) || deletedCount > 0
    }

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { isPresentingResetConfirm = true }
                    .foregroundStyle(isModifiedFromDefault ? Color.red : Color.accentColor)
            }
        }
        .confirmationDialog(
            "Reset to default sections?",
            isPresented: $isPresentingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                Task { await reset() }
            }
        } message: {
            Text("Restores the default section order and visibility for \(category.displayName). Custom sections you've created aren't deleted.")
        }
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

    private func reset() async {
        try? await repository.resetToDefault(for: category)
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
