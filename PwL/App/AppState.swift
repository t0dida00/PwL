import Foundation
import Observation

/// UI-level navigation state. Auth lives in `AccountStore`.
@MainActor
@Observable
final class AppState {
    enum Tab: Hashable {
        case dashboard
        case games
        case scoreboard
        case settings
    }

    /// The splash animation has finished at least once.
    var splashFinished = false
    var selectedTab: Tab = .games
    /// Navigation stack of the Games tab (game list → setup → play).
    var path: [Route] = []

    func resetNavigation() {
        path.removeAll()
        selectedTab = .games
    }
}

/// Every pushable screen in the Games tab.
enum Route: Hashable {
    case findNumbersSetup
    case findNumbersMatch(FindNumbersMatch)
}
