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
    @State private var searchText = ""
    @State private var selectedTemplate: HabitTemplate?
    @State private var sections: [TemplateSection] = []

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
                            Button {
                                selectedTemplate = template
                            } label: {
                                TemplateRow(template: template)
                            }
                            .buttonStyle(.plain)
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
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Edit") {
                    EditSectionsView(category: category) {
                        Task { await reload() }
                    }
                }
            }
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
    }
}

private struct TemplateRow: View {
    let template: HabitTemplate

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: template.iconSystemName)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 32)

            Text(template.title)
                .font(.body)

            Spacer()

            // §4: small Health badge for HealthKit-tracked templates.
            if template.isHealthKitTracked {
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
