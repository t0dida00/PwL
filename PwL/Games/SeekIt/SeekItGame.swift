import CoreGraphics
import Foundation
import Observation

/// Game engine for Seek It (hidden objects). Pure logic — no SwiftUI.
///
/// Race like Find Numbers: both players see the same room (same seed) and the same list
/// of target shapes, and hunt in any order. The first correct tap (decided by the host)
/// scores the object and circles it in the finder's color on both screens. Taps are in
/// canvas points (`SeekItCanvas`). A tap that isn't on an open target is a mistake with a
/// short lockout; `missesBeforeBlock` in a row block the player for `missBlock` seconds.
///
/// A match is a journey through every `SeekItLevel`, easy to hard, one room each. Finding
/// the last object of a room starts the next level on both devices (its layout comes from
/// a seed derived from the match seed, so no message is needed). Scores add up.
@MainActor
@Observable
final class SeekItGame {
    static let gameID = "seekIt"
    static let records = PlayerRecordsStore(gameID: gameID)
    nonisolated static let mistakeLockout: TimeInterval = 0.8
    nonisolated static let missesBeforeBlock = 5
    nonisolated static let missBlock: TimeInterval = 10
    /// Smallest tap radius around a target, in canvas points.
    nonisolated static let minimumHitRadius: CGFloat = 34

    enum Status: Equatable {
        case playing
        case paused
        case finished
    }

    enum TapOutcome: Equatable {
        /// An open target — claim it.
        case hit(Int)
        case miss
        case ignored
    }

    struct PlayerStats: Equatable {
        let name: String
        var found = 0
        var mistakes = 0
        /// Sum of times between finds for the objects this player won.
        var time: TimeInterval = 0
        var fastest: TimeInterval?

        var averageFind: TimeInterval? { found > 0 ? time / Double(found) : nil }
    }

    /// `player` found placement `id` on `level`. Sent host → guest.
    struct FoundEvent: Codable, Equatable, Hashable {
        let id: Int
        let player: Int
        let reaction: TimeInterval
        let level: Int
    }

    struct Result: Equatable {
        let players: [PlayerStats]
        let winnerIndex: Int?
        let time: TimeInterval
    }

    private(set) var level = SeekItLevel(1)
    private(set) var layout: SeekItLayout
    /// Target id → player who found it (current level).
    private(set) var foundBy: [Int: Int] = [:]
    private(set) var players: [PlayerStats]
    private(set) var status: Status = .playing
    private(set) var result: Result?
    private(set) var hintsLeft: [Int]
    /// Per player: game-clock time a miss block ends, while one is active.
    private(set) var blockedUntil: [TimeInterval?]
    /// Per player: wrong taps since their last find.
    private(set) var missStreak: [Int]
    /// Per player: bumped on every miss, so the view can flash.
    private(set) var missCount: [Int]

    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var resumedAt: Date?
    @ObservationIgnored private var lastFindAt: TimeInterval = 0
    @ObservationIgnored private var lockedUntil: [TimeInterval]
    @ObservationIgnored private let records: PlayerRecordsStore
    @ObservationIgnored private var seed: UInt64

    init(
        playerNames: [String] = ["Player 1", "Player 2"],
        records: PlayerRecordsStore = SeekItGame.records,
        seed: UInt64 = .random(in: .min ... .max),
        startLevel: Int = 1,
        now: Date = .now
    ) {
        let names = playerNames + (playerNames.count..<max(playerNames.count, 2)).map { "Player \($0 + 1)" }
        self.players = names.prefix(2).map { PlayerStats(name: $0) }
        self.seed = seed
        let level = SeekItLevel(startLevel)
        self.level = level
        self.layout = Self.makeLayout(level, seed: seed)
        self.hintsLeft = [level.hints, level.hints]
        self.blockedUntil = [nil, nil]
        self.missStreak = [0, 0]
        self.missCount = [0, 0]
        self.lockedUntil = [0, 0]
        self.records = records
        self.resumedAt = now
    }

    var sceneID: SeekItSceneID { level.scene }
    var scene: SeekItScene { sceneID.scene }
    var foundCount: Int { foundBy.count }
    var targetCount: Int { layout.targets.count }
    var mistakes: Int { players.reduce(0) { $0 + $1.mistakes } }

    /// Index of the player ahead, or `nil` when level.
    var leader: Int? {
        if players[0].found == players[1].found { return nil }
        return players[0].found > players[1].found ? 0 : 1
    }

    func elapsed(at now: Date = .now) -> TimeInterval {
        accumulated + (resumedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    /// Seconds left on `player`'s miss block (0 when not blocked). Pausing freezes it.
    func blockRemaining(for player: Int, at now: Date = .now) -> TimeInterval {
        guard players.indices.contains(player), let until = blockedUntil[player] else { return 0 }
        return max(0, until - elapsed(at: now))
    }

    // MARK: Taps

    /// The open target under `point` (canvas points): the nearest one whose padded
    /// radius contains the point, so a decoy drawn on top never hides a target.
    func target(at point: CGPoint) -> Int? {
        var best: (id: Int, distance: CGFloat)?
        for id in layout.targets where foundBy[id] == nil {
            guard let placement = layout.placement(id) else { continue }
            let radius = max(Self.minimumHitRadius, placement.size / 2 * level.tolerance)
            let distance = hypot(placement.center.x - point.x, placement.center.y - point.y)
            if distance <= radius, distance < (best?.distance ?? .infinity) {
                best = (id, distance)
            }
        }
        return best?.id
    }

    /// Validates a local tap without awarding it. Misses are recorded as mistakes
    /// (with lockout); `.hit` means "claim it".
    func check(_ point: CGPoint, by player: Int, at now: Date = .now) -> TapOutcome {
        guard status == .playing, players.indices.contains(player) else { return .ignored }
        let clock = elapsed(at: now)
        guard clock >= lockedUntil[player] else { return .ignored }
        blockedUntil[player] = nil
        if let id = target(at: point) { return .hit(id) }
        // Tapping something already found is harmless.
        if isOnFoundObject(point) { return .ignored }

        players[player].mistakes += 1
        missCount[player] += 1
        missStreak[player] += 1
        if missStreak[player] >= Self.missesBeforeBlock {
            missStreak[player] = 0
            lockedUntil[player] = clock + Self.missBlock
            blockedUntil[player] = clock + Self.missBlock
        } else {
            lockedUntil[player] = clock + Self.mistakeLockout
        }
        return .miss
    }

    /// Referee (host): awards target `id` to `player` if nobody has found it yet.
    /// `level` is the level the claimer saw; a claim from a finished level is dropped.
    @discardableResult
    func claim(_ id: Int, by player: Int, level seen: Int? = nil, at now: Date = .now) -> FoundEvent? {
        guard status != .finished, players.indices.contains(player), seen.map({ $0 == level.number }) ?? true,
              layout.targets.contains(id), foundBy[id] == nil else { return nil }
        let clock = elapsed(at: now)
        let event = FoundEvent(id: id, player: player, reaction: clock - lastFindAt, level: level.number)
        apply(event, clock: clock)
        return event
    }

    /// Guest: mirror a find decided by the host.
    func applyFound(_ event: FoundEvent, at now: Date = .now) {
        guard status != .finished, event.level == level.number, players.indices.contains(event.player),
              layout.targets.contains(event.id), foundBy[event.id] == nil else { return }
        apply(event, clock: elapsed(at: now))
    }

    /// Mirror the partner's miss so both devices show the same stats.
    func applyMistake(by player: Int) {
        guard players.indices.contains(player) else { return }
        players[player].mistakes += 1
    }

    /// Spends one of `player`'s hints and returns an open target to highlight
    /// (the first unfound one in list order). Local only — nothing is sent.
    func useHint(by player: Int) -> Int? {
        guard status == .playing, players.indices.contains(player), hintsLeft[player] > 0,
              let id = layout.targets.first(where: { foundBy[$0] == nil }) else { return nil }
        hintsLeft[player] -= 1
        return id
    }

    // MARK: Flow

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

    /// A new journey from level 1, freshly arranged from the shared seed.
    func restart(seed: UInt64 = .random(in: .min ... .max), at now: Date = .now) {
        self.seed = seed
        level = SeekItLevel(1)
        layout = Self.makeLayout(level, seed: seed)
        foundBy = [:]
        players = players.map { PlayerStats(name: $0.name) }
        hintsLeft = [level.hints, level.hints]
        blockedUntil = [nil, nil]
        missStreak = [0, 0]
        lockedUntil = [0, 0]
        result = nil
        accumulated = 0
        lastFindAt = 0
        resumedAt = now
        status = .playing
    }

    /// Ranking: most found, then fewest mistakes, then fastest average find.
    static func winner(of players: [PlayerStats]) -> Int? {
        guard players.count == 2 else { return nil }
        let (a, b) = (players[0], players[1])
        if a.found != b.found { return a.found > b.found ? 0 : 1 }
        if a.mistakes != b.mistakes { return a.mistakes < b.mistakes ? 0 : 1 }
        if let x = a.averageFind, let y = b.averageFind, x != y { return x < y ? 0 : 1 }
        return nil
    }

    // MARK: Private

    /// Each level's room comes from the match seed and the level number.
    private static func makeLayout(_ level: SeekItLevel, seed: UInt64) -> SeekItLayout {
        var rng = SeededGenerator(seed: seed &+ UInt64(level.number) &* 0x9E37_79B9_7F4A_7C15)
        return SeekItLayout.make(scene: level.scene.scene, level: level, using: &rng)
    }

    private func isOnFoundObject(_ point: CGPoint) -> Bool {
        foundBy.keys.contains { id in
            guard let placement = layout.placement(id) else { return false }
            let radius = max(Self.minimumHitRadius, placement.size / 2 * level.tolerance)
            return hypot(placement.center.x - point.x, placement.center.y - point.y) <= radius
        }
    }

    private func apply(_ event: FoundEvent, clock: TimeInterval) {
        foundBy[event.id] = event.player
        players[event.player].found += 1
        players[event.player].time += event.reaction
        players[event.player].fastest = min(players[event.player].fastest ?? .infinity, event.reaction)
        missStreak[event.player] = 0
        lastFindAt = clock
        guard foundCount == targetCount else { return }
        if let next = level.next {
            advance(to: next)
        } else {
            finish(at: clock)
        }
    }

    /// Room cleared: on to the next one. Lockouts and hints reset; scores carry on.
    private func advance(to next: SeekItLevel) {
        level = next
        layout = Self.makeLayout(next, seed: seed)
        foundBy = [:]
        hintsLeft = [next.hints, next.hints]
        blockedUntil = [nil, nil]
        missStreak = [0, 0]
        lockedUntil = [0, 0]
    }

    private func finish(at clock: TimeInterval) {
        accumulated = clock
        resumedAt = nil
        status = .finished
        let winner = Self.winner(of: players)
        result = Result(players: players, winnerIndex: winner, time: clock)
        for (index, player) in players.enumerated() {
            records.update(player.name) { record in
                record.games += 1
                record.duels += 1
                if index == winner { record.wins += 1 }
                record.found += player.found
                record.mistakes += player.mistakes
                record.time += player.time
                if let fastest = player.fastest {
                    record.fastestFind = min(record.fastestFind ?? .infinity, fastest)
                }
            }
        }
    }
}

/// Everything both devices need to build the identical rooms.
/// Player 0 is always the host, player 1 the guest.
struct SeekItMatch: Hashable, Codable {
    var seed: UInt64
    var playerNames: [String]
    /// Which player this device controls (differs per device).
    var localPlayer: Int

    var isHost: Bool { localPlayer == 0 }
}

/// Seek It network protocol. The host is the referee: the guest sends `claim`, the host
/// decides who was first and broadcasts `found` to both screens.
enum SeekItMessage: Codable, Equatable {
    /// Host → guest: start a match with these settings.
    case start(SeekItMatch)
    /// Guest → host: "I tapped target `id`" on `level`.
    case claim(id: Int, level: Int)
    /// Host → guest: `player` found it.
    case found(SeekItGame.FoundEvent)
    /// Either way: a player missed (keeps stats in sync).
    case mistake(player: Int)
    case pause
    case resume
    /// Either way: new arrangement with this seed.
    case restart(seed: UInt64)
    /// Either way: the sender left the game screen.
    case leave
}
