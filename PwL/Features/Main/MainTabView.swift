import SwiftUI

/// Bottom navigation: Dashboard · Games · Scoreboard · Settings.
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(AccountStore.self) private var account

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                DashboardView()
            }
            .tabItem { Label("Dashboard", systemImage: "heart.text.square.fill") }
            .tag(AppState.Tab.dashboard)

            NavigationStack(path: $appState.path) {
                GameListView()
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .findNumbersSetup:
                            FindNumbersSetupView()
                        case .findNumbersMatch(let match):
                            FindNumbersGameView(match: match)
                        }
                    }
            }
            .tabItem { Label("Games", systemImage: "gamecontroller.fill") }
            .tag(AppState.Tab.games)

            NavigationStack {
                ScoreboardView()
            }
            .tabItem { Label("Scoreboard", systemImage: "trophy.fill") }
            .tag(AppState.Tab.scoreboard)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .badge(account.isPaired ? 0 : account.incomingRequests.count)
            .tag(AppState.Tab.settings)
        }
        .tint(Theme.rose)
    }
}
