import SwiftUI

/// "Add Section" flow — a brand-new custom section (always free, per
/// APP_REDESIGN_SPEC.md §10) or one of the built-in suggested sections not
/// currently active, including premium-tagged ones like "Islamic".
///
/// As of P1 ("StoreKit + Islamic Template"), the premium gate is **real**:
/// the lock and the add-guard both read `EntitlementService` (the §10
/// centralized boundary) rather than the earlier cosmetic-only lock icon
/// that still let anyone add the section. A locked premium section can't be
/// added; tapping it surfaces a placeholder premium prompt that the Phase 8
/// paywall will replace.
struct AddSectionView: View {
    let category: HabitCategory
    var onDone: () -> Void

    @Environment(\.templateSectionRepository) private var repository
    @Environment(\.entitlementService) private var entitlementService
    @Environment(\.dismiss) private var dismiss
    @State private var availableSuggested: [TemplateSection] = []
    @State private var newSectionName = ""
    /// Section ids the user may add (premium unlocked, or the section's pack
    /// owned) — resolved through `EntitlementService.isPackUnlocked`, which is
    /// true for a generic-premium section when premium is active and for a
    /// pack section when premium is active *or* that pack is owned.
    @State private var unlockedSectionIDs: Set<String> = []
    @State private var showingPremiumPrompt = false

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
                            suggestedRow(section)
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
            .alert("Forge Premium", isPresented: $showingPremiumPrompt) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This section is part of Forge Premium. Unlock it with a subscription, or buy the pack on its own — coming soon.")
            }
            .task { await reload() }
        }
    }

    @ViewBuilder
    private func suggestedRow(_ section: TemplateSection) -> some View {
        let locked = isLocked(section)
        Button {
            Task { await handleTap(section) }
        } label: {
            HStack {
                Text(section.displayName)
                    .foregroundStyle(.primary)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: locked ? "lock.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(locked ? Color.secondary : Color.green)
            }
        }
        .accessibilityIdentifier("addSection.row.\(section.id)")
    }

    /// A section is locked only when it's premium-tier *and* the user hasn't
    /// unlocked it (premium subscription, or ownership of that section's pack).
    private func isLocked(_ section: TemplateSection) -> Bool {
        section.tier == .premium && !unlockedSectionIDs.contains(section.id)
    }

    private func reload() async {
        guard let config = try? await repository.fetchConfiguration(for: category) else { return }
        let available = config.availableSuggestedSections(for: category)
        availableSuggested = available
        // Resolve unlock per premium section (pack ownership OR premium).
        var unlocked: Set<String> = []
        for section in available where section.tier == .premium {
            if await entitlementService.isPackUnlocked(section.id) {
                unlocked.insert(section.id)
            }
        }
        unlockedSectionIDs = unlocked
    }

    private func handleTap(_ section: TemplateSection) async {
        if isLocked(section) {
            showingPremiumPrompt = true
        } else {
            await addSuggested(section)
        }
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
