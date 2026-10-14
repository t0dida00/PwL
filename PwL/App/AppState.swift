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

    /// Pops the top Games screen; safe to call twice (e.g. a double tap).
    func leaveScreen() {
        if !path.isEmpty { path.removeLast() }
    }

    func resetNavigation() {
        path.removeAll()
        selectedTab = .games
    }
}

/// Every pushable screen in the Games tab.
enum Route: Hashable {
    case findNumbersSetup
    case findNumbersMatch(FindNumbersMatch)
    case caroSetup
    case caroMatch(CaroMatch)
    case onetSetup
    case onetMatch(OnetMatch)
}
