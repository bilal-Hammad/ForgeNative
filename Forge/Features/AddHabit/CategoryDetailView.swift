import SwiftUI

/// Inside-a-category browser (APP_REDESIGN_SPEC.md §5) — styled after
/// Apple's "Add Workout" list: rounded cards, one icon per item, grouped
/// into labeled thematic sections (not the old RN app's A–Z alphabetical
/// grouping). Selecting a template opens `HabitFormView` to configure and
/// save a real `Habit`, then closes the whole Add Habit flow via
/// `onHabitCreated`.
///
/// Sections shown here are resolved through `TemplateSectionRepository`, not
/// read directly from `TemplateCatalog` — order, hidden/deleted state, and
/// custom sections are real, per-user data now (see `EditSectionsView`).
///
/// Scrubber index: a `ScrollViewReader`-backed approximation
/// (`SectionIndexStrip`), not the real UITableView `sectionIndexTitles`
/// mechanism — see that type's doc comment for why pure SwiftUI doesn't
/// have a confirmed native equivalent.
struct CategoryDetailView: View {
    let category: HabitCategory
    var onHabitCreated: () -> Void

    @Environment(\.templateSectionRepository) private var sectionRepository
    @Environment(\.habitRepository) private var habitRepository
    @State private var searchText = ""
    @State private var selectedTemplate: HabitTemplate?
    @State private var sections: [TemplateSection] = []
    @State private var deletedSectionCount = 0
    @State private var isPresentingResetConfirm = false
    /// Core-prayer template ids that already have a non-archived habit — those
    /// can't be added again (you can't pray two Fajrs in a day). Their rows
    /// render as "Added" and non-tappable. See `CorePrayerTemplate`.
    @State private var addedSingletonIDs: Set<String> = []

    /// Drives Reset's destructive styling in the confirmation dialog — same
    /// formula `EditSectionsView` used before Reset moved up to this
    /// screen's own "•••" menu (APP_REDESIGN_SPEC.md §5: "Edit" and "Reset"
    /// as sibling options under one menu, not Reset nested one screen
    /// deeper). Only the built-in portion of `sections` counts — a custom
    /// section's mere presence isn't something Reset would undo.
    private var isModifiedFromDefault: Bool {
        let builtInIDs = TemplateCatalog.sections(for: category).map(\.id)
        let currentBuiltInOrder = sections.map(\.id).filter(builtInIDs.contains)
        return currentBuiltInOrder != TemplateCatalog.defaultSectionIDs(for: category) || deletedSectionCount > 0
    }

    private var filteredSections: [TemplateSection] {
        guard !searchText.isEmpty else { return sections }
        return sections.compactMap { section in
            let matches = section.templates.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
            }
            guard !matches.isEmpty else { return nil }
            var filtered = section
            filtered.templates = matches
            return filtered
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(filteredSections) { section in
                    Section {
                        ForEach(section.templates) { template in
                            if addedSingletonIDs.contains(template.id) {
                                // Core-prayer singleton already added (non-
                                // archived) — non-tappable, with an "Added"
                                // indicator. Frees up again if archived/deleted.
                                TemplateRow(template: template, isAdded: true)
                                    .accessibilityIdentifier("templateRow.added.\(template.id)")
                            } else {
                                Button {
                                    selectedTemplate = template
                                } label: {
                                    TemplateRow(template: template)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        HStack {
                            Text(section.displayName)
                            if section.tier == .premium {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        if section.templates.isEmpty {
                            Text("No suggested habits yet in this section.")
                        }
                    }
                    .id(section.id)
                }
            }
            .listStyle(.insetGrouped)
            .overlay(alignment: .trailing) {
                if searchText.isEmpty {
                    SectionIndexStrip(
                        labels: filteredSections.map { ($0.id, String($0.displayName.prefix(1))) }
                    ) { sectionID in
                        withAnimation {
                            proxy.scrollTo(sectionID, anchor: .top)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText)
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // "•••" menu (APP_REDESIGN_SPEC.md §5): Edit and Reset as
            // sibling options, not Reset nested one screen deeper inside
            // Edit — a real IA gap this pass fixed (Reset was previously
            // only reachable from inside `EditSectionsView`).
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink {
                        EditSectionsView(category: category) {
                            Task { await reload() }
                        }
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: isModifiedFromDefault ? .destructive : nil) {
                        isPresentingResetConfirm = true
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
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
        .sheet(item: $selectedTemplate) { template in
            HabitFormView(template: template) {
                selectedTemplate = nil
                onHabitCreated()
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        guard let config = try? await sectionRepository.fetchConfiguration(for: category) else { return }
        sections = config.resolvedActiveSections(for: category)
        deletedSectionCount = config.deletedSectionIDs.count
        // Which core-prayer templates are already occupied (non-archived) —
        // refreshed on every appear, so archiving/deleting a prayer frees its
        // slot the next time this screen opens.
        let habits = (try? await habitRepository.fetchAll()) ?? []
        addedSingletonIDs = CorePrayerTemplate.addedSingletonIDs(from: habits)
    }

    private func reset() async {
        try? await sectionRepository.resetToDefault(for: category)
        await reload()
    }
}

private struct TemplateRow: View {
    let template: HabitTemplate
    /// A core-prayer singleton that's already been added (non-archived) —
    /// dimmed, with an "Added" label, and not tappable (P1 core-prayer rules).
    var isAdded: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: template.iconSystemName)
                .font(.title3)
                .foregroundStyle(isAdded ? .secondary : .primary)
                .frame(width: 32)

            Text(template.title)
                .font(.body)
                .foregroundStyle(isAdded ? .secondary : .primary)

            Spacer()

            if isAdded {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if template.isHealthKitTracked {
                // §4: small Health badge for HealthKit-tracked templates.
                HealthKitBadgeView()
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        CategoryDetailView(category: .good, onHabitCreated: {})
    }
    .environment(\.habitRepository, InMemoryHabitRepository())
    .environment(\.templateSectionRepository, InMemoryTemplateSectionRepository())
}
