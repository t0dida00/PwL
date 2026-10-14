import Foundation

/// Everything both devices need to build the identical game.
/// Player 0 is always the host, player 1 the guest.
struct FindNumbersMatch: Hashable, Codable {
    var config: FindNumbersConfig
    var seed: UInt64
    var playerNames: [String]
    /// Which player this device controls (differs per device).
    var localPlayer: Int

    var isHost: Bool { localPlayer == 0 }
}

/// Find Numbers network protocol. The host is the referee: guests send `claim`,
/// the host decides who was first and broadcasts `found` to both screens.
enum FindNumbersMessage: Codable, Equatable {
    /// Host → guest: start a match with these settings.
    case start(FindNumbersMatch)
    /// Guest → host: "I tapped the current target".
    case claim(value: Int)
    /// Host → guest: `player` won `value`.
    case found(FindNumbersGame.FindEvent)
    /// Either way: a player tapped a wrong number (keeps stats in sync).
    case mistake(player: Int)
    case pause
    case resume
    /// Either way: new board with this seed.
    case restart(seed: UInt64)
    /// Either way: the sender left the game screen.
    case leave
}
