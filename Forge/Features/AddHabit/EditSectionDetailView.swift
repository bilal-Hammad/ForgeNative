import SwiftUI

/// The `/edit-section/[id]` equivalent, reached via a section's info "i"
/// button in `EditSectionsView`. Custom sections get full editing (rename,
/// icon, add/remove habit templates within it); built-in `TemplateCatalog`
/// sections are read-only here — they're catalog content, not user data, so
/// there's nothing to rename/delete-from at this level (deleting the whole
/// section is still available from `EditSectionsView`'s minus button).
struct EditSectionDetailView: View {
    let section: TemplateSection
    var onSave: () -> Void

    @Environment(\.templateSectionRepository) private var repository
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var iconSystemName: String
    @State private var templates: [HabitTemplate]
    @State private var newTemplateName = ""

    private var isCustom: Bool { section.id.hasPrefix("custom-") }

    private static let iconChoices = [
        "folder", "star.fill", "checkmark.circle", "flame.fill", "leaf.fill",
        "heart.fill", "book.fill", "dollarsign.circle.fill", "house.fill", "person.2.fill",
    ]

    init(section: TemplateSection, onSave: @escaping () -> Void) {
        self.section = section
        self.onSave = onSave
        _name = State(initialValue: section.displayName)
        _iconSystemName = State(initialValue: "folder")
        _templates = State(initialValue: section.templates)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isCustom {
                    Section("Section") {
                        TextField("Name", text: $name)
                        Picker("Icon", selection: $iconSystemName) {
                            ForEach(Self.iconChoices, id: \.self) { icon in
                                Image(systemName: icon).tag(icon)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section("Habits") {
                        ForEach(templates) { template in
                            Text(template.title)
                        }
                        .onDelete { offsets in
                            templates.remove(atOffsets: offsets)
                        }

                        HStack {
                            TextField("New habit name", text: $newTemplateName)
                            Button("Add") {
                                templates.append(
                                    HabitTemplate(id: UUID().uuidString, title: newTemplateName, category: section.category, iconSystemName: "checkmark.circle")
                                )
                                newTemplateName = ""
                            }
                            .disabled(newTemplateName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                } else {
                    Section {
                        Text("This is a built-in section — its habits are catalog content and can't be edited here. Remove the whole section from Edit Sections if you don't want it.")
                            .foregroundStyle(.secondary)
                    }
                    Section("Habits") {
                        ForEach(templates) { template in
                            Text(template.title)
                        }
                    }
                }
            }
            .navigationTitle(section.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if isCustom {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                    }
                }
            }
        }
    }

    private func save() async {
        var updated = section
        updated.displayName = name
        updated.templates = templates
        try? await repository.updateCustomSection(updated)
        onSave()
    }
}

#Preview("Custom") {
    EditSectionDetailView(
        section: TemplateSection(id: "custom-1", category: .good, displayName: "My Section", tier: .free, templates: []),
        onSave: {}
    )
    .environment(\.templateSectionRepository, InMemoryTemplateSectionRepository())
}
