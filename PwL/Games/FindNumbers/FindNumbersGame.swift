import Foundation
import Observation

/// Game engine for Find Numbers. Pure logic — no SwiftUI — so it is unit-testable.
/// Time-dependent methods take `now` so tests can control the clock.
///
/// Every game is a race between two devices: both players hunt for the same target
/// on identical boards (same seed). Whoever taps it first scores the point.
/// The host runs `claim` as referee; the guest mirrors results with `applyFound`.
/// A wrong tap locks that player out for `mistakeLockout` seconds; `missesBeforeBlock`
/// wrong taps in a row (no find in between) block them for `missBlock` seconds.
@MainActor
@Observable
final class FindNumbersGame {
    static let gameID = "findNumbers"
    static let records = PlayerRecordsStore(gameID: gameID)
    /// Seconds a player is frozen after a wrong tap.
    nonisolated static let mistakeLockout: TimeInterval = 0.8
    /// Wrong taps in a row that trigger a long block.
    nonisolated static let missesBeforeBlock = 5
    /// Seconds a player is blocked after too many misses in a row.
    nonisolated static let missBlock: TimeInterval = 10

    enum Status: Equatable {
        case playing
        case paused
        case finished
    }

    enum TapOutcome: Equatable {
        case correct
        case wrong
        case finished
        case ignored
    }

    struct PlayerStats: Equatable {
        let name: String
        /// Numbers this player found first — their score.
        var found = 0
        var mistakes = 0
        /// Sum of reaction times (target shown → found) for numbers they won.
        var time: TimeInterval = 0
        var fastest: TimeInterval?

        var averageFind: TimeInterval? { found > 0 ? time / Double(found) : nil }
    }

    /// "`player` found `value`, `reaction` seconds after it became the target."
    struct FindEvent: Codable, Equatable {
        let value: Int
        let player: Int
        let reaction: TimeInterval
    }

    struct Result: Equatable {
        let time: TimeInterval
        let mistakes: Int
        let players: [PlayerStats]
        /// `nil` for a tie.
        let winnerIndex: Int?
    }

    let config: FindNumbersConfig
    private(set) var board: FindNumbersBoard
    /// Numbers in the order they must be found.
    private(set) var sequence: [Int]
    /// Found number → index of the player who found it first.
    private(set) var foundBy: [Int: Int] = [:]
    private(set) var players: [PlayerStats]
    private(set) var status: Status = .playing
    private(set) var result: Result?
    /// Per player: value of their last wrong tap while it is flashing / they are locked out.
    private(set) var wrongValues: [Int?]
    /// Per player: wrong taps since their last find (or last block).
    private(set) var missStreak: [Int]
    /// Per player: game-clock time a miss block ends, while one is active.
    private(set) var blockedUntil: [TimeInterval?]

    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var resumedAt: Date?
    /// Game-clock time when the current target appeared.
    @ObservationIgnored private var targetShownAt: TimeInterval = 0
    /// Game-clock time until which each player's taps are ignored.
    @ObservationIgnored private var lockedUntil: [TimeInterval]
    @ObservationIgnored private let records: PlayerRecordsStore
    @ObservationIgnored private let paletteCount: Int
    @ObservationIgnored private var wrongResetTasks: [Int: Task<Void, Never>] = [:]

    init(
        config: FindNumbersConfig,
        playerNames: [String] = ["Player 1", "Player 2"],
        paletteCount: Int = 1,
        records: PlayerRecordsStore = FindNumbersGame.records,
        seed: UInt64 = .random(in: .min ... .max),
        now: Date = .now
    ) {
        self.config = config
        let names = playerNames + (playerNames.count..<max(playerNames.count, 2)).map { "Player \($0 + 1)" }
        self.players = names.prefix(2).map { PlayerStats(name: $0) }
        self.wrongValues = [nil, nil]
        self.lockedUntil = [0, 0]
        self.missStreak = [0, 0]
        self.blockedUntil = [nil, nil]
        self.paletteCount = paletteCount
        self.records = records
        var rng = SeededGenerator(seed: seed)
        self.board = FindNumbersBoardGenerator.make(config: config, paletteCount: paletteCount, using: &rng)
        self.sequence = config.makeSequence(using: &rng)
        self.resumedAt = now
    }

    var foundCount: Int { foundBy.count }
    var mistakes: Int { players.reduce(0) { $0 + $1.mistakes } }
    var target: Int? { foundCount < sequence.count ? sequence[foundCount] : nil }

    /// Index of the player currently ahead on points, or `nil` when level.
    var leader: Int? {
        let sorted = players.indices.sorted { players[$0].found > players[$1].found }
        return players[sorted[0]].found > players[sorted[1]].found ? sorted[0] : nil
    }

    func elapsed(at now: Date = .now) -> TimeInterval {
        accumulated + (resumedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    /// Seconds left on `player`'s miss block (0 when not blocked). Pausing freezes it.
    func blockRemaining(for player: Int, at now: Date = .now) -> TimeInterval {
        guard players.indices.contains(player), let until = blockedUntil[player] else { return 0 }
        return max(0, until - elapsed(at: now))
    }

    /// Host: check the tap and, if it is the target, award it immediately.
    @discardableResult
    func tap(_ value: Int, by player: Int = 0, at now: Date = .now) -> TapOutcome {
        let outcome = check(value, by: player, at: now)
        guard outcome == .correct, claim(value, by: player, at: now) != nil else { return outcome }
        return status == .finished ? .finished : .correct
    }

    /// Validates a local tap without awarding it. Wrong taps are recorded as mistakes
    /// (with lockout); `.correct` means "this is the current target — claim it".
    func check(_ value: Int, by player: Int, at now: Date = .now) -> TapOutcome {
        guard status == .playing, players.indices.contains(player), let target, foundBy[value] == nil else {
            return .ignored
        }
        let clock = elapsed(at: now)
        guard clock >= lockedUntil[player] else { return .ignored }
        blockedUntil[player] = nil
        guard value == target else {
            players[player].mistakes += 1
            missStreak[player] += 1
            if missStreak[player] >= Self.missesBeforeBlock {
                missStreak[player] = 0
                lockedUntil[player] = clock + Self.missBlock
                blockedUntil[player] = clock + Self.missBlock
            } else {
                lockedUntil[player] = clock + Self.mistakeLockout
            }
            flashWrong(value, for: player)
            return .wrong
        }
        return .correct
    }

    /// Referee (host): awards `value` to `player` if it is still the open target.
    /// Returns the event to broadcast, or `nil` if someone already got it.
    @discardableResult
    func claim(_ value: Int, by player: Int, at now: Date = .now) -> FindEvent? {
        guard status != .finished, players.indices.contains(player), value == target else { return nil }
        let clock = elapsed(at: now)
        let event = FindEvent(value: value, player: player, reaction: clock - targetShownAt)
        apply(event, clock: clock)
        return event
    }

    /// Guest: mirror a find decided by the host.
    func applyFound(_ event: FindEvent, at now: Date = .now) {
        guard status != .finished, players.indices.contains(event.player), event.value == target else { return }
        apply(event, clock: elapsed(at: now))
    }

    /// Mirror the partner's wrong tap so both devices show the same stats.
    func applyMistake(by player: Int) {
        guard players.indices.contains(player) else { return }
        players[player].mistakes += 1
    }

    private func apply(_ event: FindEvent, clock: TimeInterval) {
        players[event.player].found += 1
        players[event.player].time += event.reaction
        players[event.player].fastest = min(players[event.player].fastest ?? .infinity, event.reaction)
        foundBy[event.value] = event.player
        missStreak[event.player] = 0
        targetShownAt = clock
        if foundCount == config.count { finish(at: clock) }
    }

    func pause(at now: Date = .now) {
        guard status == .playing else { return }
        accumulated = elapsed(at: now)
        resumedAt = nil
        status = .paused
    }

    func resume(at now: Date = .now) {
        guard status == .paused else { return }
        resumedAt = now
        status = .playing
    }

    /// Same settings, freshly shuffled board from the shared seed.
    func restart(seed: UInt64 = .random(in: .min ... .max), at now: Date = .now) {
        var rng = SeededGenerator(seed: seed)
        board = FindNumbersBoardGenerator.make(config: config, paletteCount: paletteCount, using: &rng)
        sequence = config.makeSequence(using: &rng)
        foundBy = [:]
        players = players.map { PlayerStats(name: $0.name) }
        wrongValues = Array(repeating: nil, count: players.count)
        lockedUntil = Array(repeating: 0, count: players.count)
        missStreak = Array(repeating: 0, count: players.count)
        blockedUntil = Array(repeating: nil, count: players.count)
        wrongResetTasks.values.forEach { $0.cancel() }
        wrongResetTasks = [:]
        result = nil
        accumulated = 0
        targetShownAt = 0
        resumedAt = now
        status = .playing
    }

    /// Ranking: most numbers found, then fewest mistakes, then fastest average.
    static func winner(of players: [PlayerStats]) -> Int? {
        guard players.count > 1 else { return nil }
        func ranksAhead(_ a: PlayerStats, _ b: PlayerStats) -> Bool {
            if a.found != b.found { return a.found > b.found }
            if a.mistakes != b.mistakes { return a.mistakes < b.mistakes }
            return (a.averageFind ?? .infinity) < (b.averageFind ?? .infinity)
        }
        let order = players.indices.sorted { ranksAhead(players[$0], players[$1]) }
        return ranksAhead(players[order[0]], players[order[1]]) ? order[0] : nil
    }

    private func finish(at clock: TimeInterval) {
        accumulated = clock
        resumedAt = nil
        let winnerIndex = Self.winner(of: players)

        for (index, player) in players.enumerated() {
            records.update(player.name) { record in
                record.games += 1
                record.found += player.found
                record.mistakes += player.mistakes
                record.time += player.time
                if let fastest = player.fastest {
                    record.fastestFind = min(record.fastestFind ?? .infinity, fastest)
                }
                record.duels += 1
                if index == winnerIndex { record.wins += 1 }
            }
        }

        result = Result(
            time: clock,
            mistakes: mistakes,
            players: players,
            winnerIndex: winnerIndex
        )
        status = .finished
    }

    private func flashWrong(_ value: Int, for player: Int) {
        wrongValues[player] = value
        wrongResetTasks[player]?.cancel()
        wrongResetTasks[player] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.mistakeLockout))
            guard !Task.isCancelled else { return }
            self?.wrongValues[player] = nil
        }
    }
}
