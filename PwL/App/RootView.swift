import SwiftUI

/// Splash → Login (Google) → Main tabs.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AccountStore.self) private var account
    @Environment(NearbyService.self) private var nearby
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if !appState.splashFinished || account.state == .loading {
                LoadingView { appState.splashFinished = true }
                    .transition(.opacity)
            } else if account.state == .signedOut {
                LoginView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.splashFinished)
        .animation(.easeInOut(duration: 0.35), value: account.state)
        .task { await account.restore() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: account.appBecameActive()
            // Inactive = app switcher, Control Center, a call…: the user isn't in the app.
            case .inactive, .background: Task { await account.appWentToBackground() }
            default: break
            }
        }
        .onChange(of: account.state) { _, state in
            if state == .signedOut {
                nearby.stop()
                appState.resetNavigation()
            }
        }
    }
}
