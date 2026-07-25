import SwiftUI

/// "Add Section" flow — a brand-new custom section (always free, per
/// APP_REDESIGN_SPEC.md §10) or one of the built-in suggested sections not
/// currently active, including premium-tagged ones like "Islamic": no
/// payment gate yet, per the §10 timing decision (real StoreKit 2
/// entitlement checks land in Phase 4+).
struct AddSectionView: View {
    let category: HabitCategory
    var onDone: () -> Void

    @Environment(\.templateSectionRepository) private var repository
    @Environment(\.dismiss) private var dismiss
    @State private var availableSuggested: [TemplateSection] = []
    @State private var newSectionName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("New Custom Section") {
                    HStack {
                        TextField("Section Name", text: $newSectionName)
                        Button("Add") {
                            Task { await addCustom() }
                        }
                        .disabled(newSectionName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Suggested Sections") {
                    if availableSuggested.isEmpty {
                        Text("No suggested sections left to add.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableSuggested) { section in
                            Button {
                                Task { await addSuggested(section) }
                            } label: {
                                HStack {
                                    Text(section.displayName)
                                        .foregroundStyle(.primary)
                                    if section.tier == .premium {
                                        Image(systemName: "lock.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        guard let config = try? await repository.fetchConfiguration(for: category) else { return }
        availableSuggested = config.availableSuggestedSections(for: category)
    }

    private func addCustom() async {
        let section = TemplateSection(
            id: "custom-\(UUID().uuidString)",
            category: category,
            displayName: newSectionName,
            tier: .free,
            templates: []
        )
        try? await repository.addCustomSection(section)
        onDone()
    }

    private func addSuggested(_ section: TemplateSection) async {
        try? await repository.addSuggestedSection(sectionID: section.id, for: category)
        onDone()
    }
}

#Preview {
    AddSectionView(category: .good, onDone: {})
        .environment(\.templateSectionRepository, InMemoryTemplateSectionRepository())
}
