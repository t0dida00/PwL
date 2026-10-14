import SwiftUI

/// Bottom navigation: Dashboard · Games · Scoreboard · Settings.
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(AccountStore.self) private var account
    @Environment(NearbyService.self) private var nearby

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
                        case .caroSetup:
                            CaroSetupView()
                        case .caroMatch(let match):
                            CaroGameView(match: match)
                        case .onetSetup:
                            OnetSetupView()
                        case .onetMatch(let match):
                            OnetGameView(match: match)
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
        // Back on the game list = out of every lobby: drop the connection.
        .onChange(of: appState.path.isEmpty) { _, isEmpty in
            if isEmpty { nearby.leaveLobby() }
        }
    }
}
