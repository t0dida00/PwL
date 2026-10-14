import Foundation
import Observation

/// Board settings both devices share. The board is always the classic 9 × 16
/// (played in landscape): 144 tiles = each of the 36 flags exactly 4 times.
struct OnetConfig: Hashable, Codable {
    static let rows = 9
    static let columns = 16
    static let pairs = rows * columns / 2

    /// How many levels a match runs through (always starting at level 1).
    enum Levels: String, CaseIterable, Codable {
        case one, three, all

        var count: Int {
            switch self {
            case .one: 1
            case .three: 3
            case .all: OnetLevel.allCases.count
            }
        }

        var title: String {
            switch self {
            case .one: "1 level"
            case .three: "3 levels"
            case .all: "All \(OnetLevel.allCases.count)"
            }
        }
    }

    /// How many different tile faces exist (see `OnetTileFace`).
    static let kindCount = 36

    var levels: Levels = .three

    var rows: Int { Self.rows }
    var columns: Int { Self.columns }
}

/// Classic Pikachu levels: after every match the remaining tiles slide this way.
enum OnetLevel: Int, CaseIterable, Codable {
    case classic = 1
    case fallDown
    case floatUp
    case slideLeft
    case slideRight
    case squeezeIn
    case splitApart
    case squash
    case spreadOut

    var title: String {
        switch self {
        case .classic: "Classic"
        case .fallDown: "Tiles fall down"
        case .floatUp: "Tiles float up"
        case .slideLeft: "Tiles slide left"
        case .slideRight: "Tiles slide right"
        case .squeezeIn: "Squeeze to the middle"
        case .splitApart: "Split to the sides"
        case .squash: "Squash to the middle"
        case .spreadOut: "Spread to top & bottom"
        }
    }

    var symbol: String {
        switch self {
        case .classic: "square.grid.2x2.fill"
        case .fallDown: "arrow.down"
        case .floatUp: "arrow.up"
        case .slideLeft: "arrow.left"
        case .slideRight: "arrow.right"
        case .squeezeIn: "arrow.right.and.line.vertical.and.arrow.left"
        case .splitApart: "arrow.left.and.line.vertical.and.arrow.right"
        case .squash: "arrow.down.and.line.horizontal.and.arrow.up"
        case .spreadOut: "arrow.up.and.line.horizontal.and.arrow.down"
        }
    }

    var shifts: Bool { self != .classic }

    /// Cell lines to compact: tiles in each line slide toward the line's first cell.
    func lines(rows: Int, columns: Int) -> [[Int]] {
        func cell(_ r: Int, _ c: Int) -> Int { r * columns + c }
        let midColumn = columns / 2, midRow = rows / 2
        switch self {
        case .classic:
            return []
        case .fallDown:
            return (0..<columns).map { c in (0..<rows).reversed().map { cell($0, c) } }
        case .floatUp:
            return (0..<columns).map { c in (0..<rows).map { cell($0, c) } }
        case .slideLeft:
            return (0..<rows).map { r in (0..<columns).map { cell(r, $0) } }
        case .slideRight:
            return (0..<rows).map { r in (0..<columns).reversed().map { cell(r, $0) } }
        case .squeezeIn:
            return (0..<rows).flatMap { r in
                [(0..<midColumn).reversed().map { cell(r, $0) }, (midColumn..<columns).map { cell(r, $0) }]
            }
        case .splitApart:
            return (0..<rows).flatMap { r in
                [(0..<midColumn).map { cell(r, $0) }, (midColumn..<columns).reversed().map { cell(r, $0) }]
            }
        case .squash:
            return (0..<columns).flatMap { c in
                [(0..<midRow).reversed().map { cell($0, c) }, (midRow..<rows).map { cell($0, c) }]
            }
        case .spreadOut:
            return (0..<columns).flatMap { c in
                [(0..<midRow).map { cell($0, c) }, (midRow..<rows).reversed().map { cell($0, c) }]
            }
        }
    }
}

/// A point on the board grid padded by one empty ring, so paths can run around the
/// outside. Row/column `-1` and `rows`/`columns` are outside the tiles.
struct OnetPoint: Hashable, Codable {
    var row: Int
    var column: Int
}

/// Builds the shuffled tile layout: every face appears an even number of times
/// (4 where possible), and the start always has at least one playable pair.
enum OnetBoardGenerator {
    static func make(config: OnetConfig, using rng: inout some RandomNumberGenerator) -> [Int?] {
        let count = config.rows * config.columns
        var kinds: [Int] = []
        var kind = 0
        while kinds.count < count {
            let copies = min(4, count - kinds.count)
            kinds += Array(repeating: kind % OnetConfig.kindCount, count: copies)
            kind += 1
        }
        var tiles: [Int?] = kinds.shuffled(using: &rng)
        for _ in 0..<50 where !OnetGame.hasMove(in: tiles, rows: config.rows, columns: config.columns) {
            tiles = kinds.shuffled(using: &rng)
        }
        return tiles
    }
}

/// Game engine for Onet ("Pikachu" link game). Pure logic — no SwiftUI.
///
/// Race like Find Numbers: both players see the same board (same seed) and match pairs
/// whenever they like. Two tiles match when they show the same face and can be linked by
/// a path of at most three straight segments (two turns) through empty cells, including
/// the ring around the board. The host referees claims (`claim`) and broadcasts matches;
/// the guest mirrors them (`applyMatch`). When no pair is playable, both devices
/// reshuffle the remaining tiles with the same derived seed.
///
/// Matches run through `config.levels` levels: from level 2 on, tiles slide after every
/// match (`OnetLevel`). Clearing a board starts the next level with a board from a seed
/// derived from the match seed, so both devices advance in step without a message.
/// Scores add up across levels.
@MainActor
@Observable
final class OnetGame {
    static let gameID = "onet"
    static let records = PlayerRecordsStore(gameID: gameID)
    /// Seconds a player is frozen after picking two different faces.
    nonisolated static let mistakeLockout: TimeInterval = 0.8

    enum Status: Equatable {
        case playing
        case paused
        case finished
    }

    enum CheckOutcome: Equatable {
        /// Same face and linkable — claim it.
        case match([OnetPoint])
        /// Same face but no path of ≤ 2 turns (not a mistake).
        case noPath
        /// Different faces: a mistake.
        case wrong
        case ignored
    }

    struct PlayerStats: Equatable {
        var name: String
        var pairs = 0
        var mistakes = 0
    }

    /// A pair removed by `player`. Sent host → guest.
    struct PairEvent: Codable, Equatable, Hashable {
        let first: Int
        let second: Int
        let player: Int
    }

    /// The most recent match, with its link path, for the line animation.
    struct Match: Equatable {
        let event: PairEvent
        let path: [OnetPoint]
        let serial: Int
    }

    struct Result: Equatable {
        let players: [PlayerStats]
        let winnerIndex: Int?
        let time: TimeInterval
    }

    let config: OnetConfig
    /// Face of each cell (row-major), `nil` once removed.
    private(set) var tiles: [Int?]
    /// Stable identity of the tile in each cell (moves with it when tiles slide).
    private(set) var tileIDs: [Int?]
    /// Current level (1-based).
    private(set) var level: OnetLevel = .classic
    /// Bumped on every board change; claims made on an older board are rejected
    /// on sliding levels, where cells may now hold other tiles.
    private(set) var revision = 0
    private(set) var players: [PlayerStats]
    private(set) var status: Status = .playing
    private(set) var result: Result?
    private(set) var lastMatch: Match?
    /// Times the board reshuffled because no pair was playable.
    private(set) var shuffleCount = 0
    /// Per player: the two cells of their last wrong pick while it flashes.
    private(set) var wrongPair: [[Int]?]

    @ObservationIgnored private var seed: UInt64
    @ObservationIgnored private var nextTileID = 0
    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var resumedAt: Date?
    @ObservationIgnored private var lockedUntil: [TimeInterval]
    @ObservationIgnored private let records: PlayerRecordsStore
    @ObservationIgnored private var wrongResetTasks: [Int: Task<Void, Never>] = [:]

    init(
        config: OnetConfig,
        playerNames: [String] = ["Player 1", "Player 2"],
        records: PlayerRecordsStore = OnetGame.records,
        seed: UInt64 = .random(in: .min ... .max),
        layout: [Int?]? = nil,
        now: Date = .now
    ) {
        self.config = config
        let names = playerNames + (playerNames.count..<max(playerNames.count, 2)).map { "Player \($0 + 1)" }
        self.players = names.prefix(2).map { PlayerStats(name: $0) }
        self.wrongPair = [nil, nil]
        self.lockedUntil = [0, 0]
        self.records = records
        self.seed = seed
        var rng = SeededGenerator(seed: seed)
        let tiles = layout ?? OnetBoardGenerator.make(config: config, using: &rng)
        self.tiles = tiles
        self.tileIDs = tiles.indices.map { tiles[$0] == nil ? nil : $0 }
        self.nextTileID = tiles.count
        self.resumedAt = now
    }

    var levelCount: Int { config.levels.count }

    var rows: Int { config.rows }
    var columns: Int { config.columns }
    var pairsLeft: Int { tiles.lazy.compactMap { $0 }.count / 2 }

    /// Index of the player ahead on pairs, or `nil` when level.
    var leader: Int? {
        if players[0].pairs == players[1].pairs { return nil }
        return players[0].pairs > players[1].pairs ? 0 : 1
    }

    func elapsed(at now: Date = .now) -> TimeInterval {
        accumulated + (resumedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    func isLocked(_ player: Int, at now: Date = .now) -> Bool {
        players.indices.contains(player) && elapsed(at: now) < lockedUntil[player]
    }

    // MARK: Moves

    /// Validates a local pick of two cells without awarding it. Different faces count as
    /// a mistake (with lockout); `.match` means "claim it".
    func check(_ first: Int, _ second: Int, by player: Int, at now: Date = .now) -> CheckOutcome {
        guard status == .playing, players.indices.contains(player), first != second,
              tiles.indices.contains(first), tiles.indices.contains(second),
              let a = tiles[first], let b = tiles[second], !isLocked(player, at: now) else { return .ignored }
        guard a == b else {
            players[player].mistakes += 1
            lockedUntil[player] = elapsed(at: now) + Self.mistakeLockout
            flashWrong([first, second], for: player)
            return .wrong
        }
        guard let path = path(from: first, to: second) else { return .noPath }
        return .match(path)
    }

    /// Referee (host): removes the pair for `player` if it is still valid on this board.
    /// Returns the event to broadcast, or `nil` if it is gone / no longer linkable.
    /// `revision` is the board the claimer saw; on sliding levels an older one is rejected.
    @discardableResult
    func claim(_ first: Int, _ second: Int, by player: Int, revision seen: Int? = nil) -> PairEvent? {
        if let seen, level.shifts, seen != revision { return nil }
        guard status != .finished, players.indices.contains(player),
              tiles.indices.contains(first), tiles.indices.contains(second),
              let a = tiles[first], a == tiles[second], let path = path(from: first, to: second) else { return nil }
        let event = PairEvent(first: first, second: second, player: player)
        apply(event, path: path)
        return event
    }

    /// Guest: mirror a match decided by the host.
    func applyMatch(_ event: PairEvent) {
        guard status != .finished, players.indices.contains(event.player),
              tiles.indices.contains(event.first), tiles.indices.contains(event.second),
              tiles[event.first] != nil, tiles[event.second] != nil else { return }
        let path = path(from: event.first, to: event.second) ?? [point(event.first), point(event.second)]
        apply(event, path: path)
    }

    /// Mirror the partner's wrong pick so both devices show the same stats.
    func applyMistake(by player: Int) {
        guard players.indices.contains(player) else { return }
        players[player].mistakes += 1
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

    /// Same settings, a fresh board from the shared seed.
    func restart(seed: UInt64 = .random(in: .min ... .max), at now: Date = .now) {
        self.seed = seed
        var rng = SeededGenerator(seed: seed)
        setBoard(OnetBoardGenerator.make(config: config, using: &rng))
        level = .classic
        revision = 0
        players = players.map { PlayerStats(name: $0.name) }
        wrongPair = [nil, nil]
        lockedUntil = [0, 0]
        wrongResetTasks.values.forEach { $0.cancel() }
        wrongResetTasks = [:]
        lastMatch = nil
        shuffleCount = 0
        result = nil
        accumulated = 0
        resumedAt = now
        status = .playing
    }

    /// Ranking: most pairs, then fewest mistakes; otherwise a tie.
    static func winner(of players: [PlayerStats]) -> Int? {
        guard players.count == 2 else { return nil }
        let (a, b) = (players[0], players[1])
        if a.pairs != b.pairs { return a.pairs > b.pairs ? 0 : 1 }
        if a.mistakes != b.mistakes { return a.mistakes < b.mistakes ? 0 : 1 }
        return nil
    }

    // MARK: Paths

    /// The link between two cells as corner points (start, up to two turns, end),
    /// or `nil` if they don't share a face or need more than two turns.
    func path(from first: Int, to second: Int) -> [OnetPoint]? {
        Self.path(from: first, to: second, in: tiles, rows: rows, columns: columns)
    }

    nonisolated static func path(from first: Int, to second: Int, in tiles: [Int?], rows: Int, columns: Int) -> [OnetPoint]? {
        guard first != second, let face = tiles[first], tiles[second] == face else { return nil }
        let start = OnetPoint(row: first / columns, column: first % columns)
        let end = OnetPoint(row: second / columns, column: second % columns)

        func isOpen(_ p: OnetPoint) -> Bool {
            guard (0..<rows).contains(p.row), (0..<columns).contains(p.column) else { return true } // outer ring
            return tiles[p.row * columns + p.column] == nil
        }
        func inBounds(_ p: OnetPoint) -> Bool {
            (-1...rows).contains(p.row) && (-1...columns).contains(p.column)
        }

        // Breadth-first by straight segments: level k holds points reachable with k segments.
        var parent: [OnetPoint: OnetPoint] = [start: start]
        var frontier = [start]
        for _ in 0..<3 {
            var next: [OnetPoint] = []
            for p in frontier {
                for (dr, dc) in [(0, 1), (1, 0), (0, -1), (-1, 0)] {
                    var q = OnetPoint(row: p.row + dr, column: p.column + dc)
                    while inBounds(q) {
                        if q == end {
                            var corners = [end, p]
                            var cursor = p
                            while cursor != start, let previous = parent[cursor] {
                                corners.append(previous)
                                cursor = previous
                            }
                            return corners.reversed()
                        }
                        guard isOpen(q) else { break }
                        if parent[q] == nil {
                            parent[q] = p
                            next.append(q)
                        }
                        q = OnetPoint(row: q.row + dr, column: q.column + dc)
                    }
                }
            }
            frontier = next
        }
        return nil
    }

    /// Whether any pair on the board can be linked.
    nonisolated static func hasMove(in tiles: [Int?], rows: Int, columns: Int) -> Bool {
        var byFace: [Int: [Int]] = [:]
        for (index, face) in tiles.enumerated() {
            if let face { byFace[face, default: []].append(index) }
        }
        for cells in byFace.values where cells.count >= 2 {
            for i in 0..<cells.count {
                for j in (i + 1)..<cells.count where path(from: cells[i], to: cells[j], in: tiles, rows: rows, columns: columns) != nil {
                    return true
                }
            }
        }
        return false
    }

    // MARK: Private

    private func point(_ index: Int) -> OnetPoint {
        OnetPoint(row: index / columns, column: index % columns)
    }

    private func apply(_ event: PairEvent, path: [OnetPoint]) {
        tiles[event.first] = nil
        tiles[event.second] = nil
        tileIDs[event.first] = nil
        tileIDs[event.second] = nil
        players[event.player].pairs += 1
        lastMatch = Match(event: event, path: path, serial: (lastMatch?.serial ?? 0) + 1)
        revision += 1

        if pairsLeft == 0 {
            if level.rawValue < levelCount, let next = OnetLevel(rawValue: level.rawValue + 1) {
                start(next)
            } else {
                finish()
            }
            return
        }
        slide()
        if !Self.hasMove(in: tiles, rows: rows, columns: columns) {
            reshuffle()
        }
    }

    /// Compacts each of the level's lines toward its first cell, keeping tile order.
    private func slide() {
        for line in level.lines(rows: rows, columns: columns) {
            let kept = line.filter { tiles[$0] != nil }.map { (tiles[$0], tileIDs[$0]) }
            for (offset, cell) in line.enumerated() {
                tiles[cell] = offset < kept.count ? kept[offset].0 : nil
                tileIDs[cell] = offset < kept.count ? kept[offset].1 : nil
            }
        }
    }

    /// New board for `next`, from a seed both devices derive the same way.
    private func start(_ next: OnetLevel) {
        level = next
        var rng = SeededGenerator(seed: seed &+ UInt64(next.rawValue) &* 0xD1B5_4A32_D192_ED03)
        setBoard(OnetBoardGenerator.make(config: config, using: &rng))
        wrongPair = [nil, nil]
        revision += 1
    }

    private func setBoard(_ faces: [Int?]) {
        tiles = faces
        tileIDs = faces.indices.map { faces[$0] == nil ? nil : nextTileID + $0 }
        nextTileID += faces.count
    }

    /// Same derived seed on both devices, so the reshuffled boards stay identical.
    private func reshuffle() {
        let cells = tiles.indices.filter { tiles[$0] != nil }
        let faces = cells.compactMap { tiles[$0] }
        for attempt in 0..<50 {
            shuffleCount += 1
            var rng = SeededGenerator(seed: seed &+ UInt64(shuffleCount) &* 0x9E37_79B9_7F4A_7C15)
            let shuffled = faces.shuffled(using: &rng)
            for (cell, face) in zip(cells, shuffled) { tiles[cell] = face }
            revision += 1
            if Self.hasMove(in: tiles, rows: rows, columns: columns) || attempt == 49 { return }
        }
    }

    private func finish() {
        let time = elapsed()
        accumulated = time
        resumedAt = nil
        status = .finished
        let winner = Self.winner(of: players)
        result = Result(players: players, winnerIndex: winner, time: time)
        for (index, player) in players.enumerated() {
            records.update(player.name) { record in
                record.games += 1
                record.duels += 1
                if index == winner { record.wins += 1 }
                record.found += player.pairs
                record.mistakes += player.mistakes
                record.time += time
            }
        }
    }

    private func flashWrong(_ cells: [Int], for player: Int) {
        wrongPair[player] = cells
        wrongResetTasks[player]?.cancel()
        wrongResetTasks[player] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.mistakeLockout))
            guard !Task.isCancelled else { return }
            self?.wrongPair[player] = nil
        }
    }
}

/// Everything both devices need to build the identical board.
/// Player 0 is always the host, player 1 the guest.
struct OnetMatch: Hashable, Codable {
    var config: OnetConfig
    var seed: UInt64
    var playerNames: [String]
    /// Which player this device controls (differs per device).
    var localPlayer: Int

    var isHost: Bool { localPlayer == 0 }
}

/// Onet network protocol. The host is the referee: the guest sends `claim`, the host
/// decides and broadcasts `matched` (or `rejected` if the pair was already taken).
enum OnetMessage: Codable, Equatable {
    /// Host → guest: start a match with these settings.
    case start(OnetMatch)
    /// Guest → host: "I linked these two cells" on board `revision`.
    case claim(first: Int, second: Int, revision: Int)
    /// Host → guest: `player` removed this pair.
    case matched(OnetGame.PairEvent)
    /// Host → guest: that claim lost the race.
    case rejected(first: Int, second: Int)
    /// Either way: a player picked two different faces (keeps stats in sync).
    case mistake(player: Int)
    case pause
    case resume
    /// Either way: new board with this seed.
    case restart(seed: UInt64)
    /// Either way: the sender left the game screen.
    case leave
}
