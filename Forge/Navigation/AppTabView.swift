import SwiftUI

/// Tab identity for `AppTabView`'s selection binding — exists only so
/// `MoodCheckInRouter` has something to switch the tab bar to
/// programmatically (see `body`'s `.onChange` below); nothing else in the
/// app needed a tag before this.
private enum AppTab: Hashable {
    case home, progress, profile
}

/// The app's root navigation shell — Home / Progress / Profile.
///
/// On iOS 26, SwiftUI's own `TabView` renders with the real native Liquid
/// Glass tab bar automatically — no custom glass/gesture work needed here,
/// unlike the React Native version's hand-built `PanResponder`-driven bar.
/// (APP_REDESIGN_SPEC.md §2: "This is largely already built as the native
/// Liquid Glass TabView — apply the same icon+label treatment there.")
struct AppTabView: View {
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Progress", systemImage: "chart.bar.fill", value: AppTab.progress) {
                ProgressScreenView()
            }
            Tab("Profile", systemImage: "person.fill", value: AppTab.profile) {
                ProfileView()
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        // §13's mood reminder notification routes here — see
        // `MoodCheckInRouter`'s doc comment for why "opens straight to the
        // card" means "switch to Home," not a separate screen/sheet.
        .onChange(of: MoodCheckInRouter.shared.pendingMoodCheckInPrompt) { _, pending in
            guard pending else { return }
            selectedTab = .home
            MoodCheckInRouter.shared.pendingMoodCheckInPrompt = false
        }
    }
}

#Preview {
    AppTabView()
        .environment(\.habitRepository, InMemoryHabitRepository())
}
