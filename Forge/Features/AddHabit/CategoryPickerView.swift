import SwiftUI

/// Top-level "Add Habit" entry point (APP_REDESIGN_SPEC.md §4). Deliberately
/// avoids the word "Templates" anywhere in this flow's UI text, shows exactly
/// 3 categories (Good/Bad/To-Do — "Health" no longer exists as its own
/// category), has no search icon, and uses card-based groupings rather than
/// a plain grouped list with chevrons.
///
/// `onHabitCreated` is threaded down through `CategoryDetailView` rather than
/// relying on `@Environment(\.dismiss)` from a deeply-pushed view — dismiss
/// would only pop this view's own NavigationStack, not close the sheet Home
/// presented this whole flow in.
///
/// The floating "+" (bottom-right) is a shortcut straight to a from-scratch
/// custom habit (`HabitFormView(customHabitCategory:)`), for anyone who
/// already knows what they want and doesn't need to browse a category's
/// sections first — category itself is picked inside that form instead,
/// since this button skips the step that would normally have fixed one.
struct CategoryPickerView: View {
    var onHabitCreated: () -> Void

    @State private var isPresentingCustomHabit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(HabitCategory.allCases) { category in
                        NavigationLink {
                            CategoryDetailView(category: category, onHabitCreated: onHabitCreated)
                        } label: {
                            CategoryCard(category: category)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    isPresentingCustomHabit = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .padding(20)
            }
            .navigationTitle("Add Habit")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isPresentingCustomHabit) {
                HabitFormView(customHabitCategory: .good) {
                    isPresentingCustomHabit = false
                    onHabitCreated()
                }
            }
        }
    }
}

private struct CategoryCard: View {
    let category: HabitCategory

    private var symbolName: String {
        switch category {
        case .good: "checkmark.circle.fill"
        case .bad: "xmark.circle.fill"
        case .todo: "list.bullet.circle.fill"
        }
    }

    private var tint: Color {
        switch category {
        case .good: .green
        case .bad: .red
        case .todo: .blue
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbolName)
                .font(.system(size: 32))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.displayName)
                    .font(.title3.weight(.semibold))
                Text(sectionCountLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var sectionCountLabel: String {
        let count = TemplateCatalog.sections(for: category).count
        return "\(count) section\(count == 1 ? "" : "s")"
    }
}

#Preview {
    CategoryPickerView(onHabitCreated: {})
}
