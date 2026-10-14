import GoogleSignIn
import SwiftUI

@main
struct PwLApp: App {
    @State private var appState = AppState()
    @State private var audio = AudioManager()
    @State private var nearby = NearbyService()
    @State private var account: AccountStore

    init() {
        // Firebase when GoogleService-Info.plist is bundled, otherwise the local test backend.
        let backend: AccountBackend = FirebaseAccountBackend.configureIfPossible()
            ? FirebaseAccountBackend()
            : LocalAccountBackend()
        _account = State(initialValue: AccountStore(backend: backend))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(audio)
                .environment(nearby)
                .environment(account)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}
