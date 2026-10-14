import Foundation
import Observation

/// Settings both devices share. Cells are indexed row-major: `row * size + column`.
struct CaroConfig: Hashable, Codable {
    enum Rule: String, CaseIterable, Codable {
        /// Five or more in a row wins.
        case free
        /// Vietnamese rule: a line blocked by the opponent at both ends doesn't win.
        case blockedEnds

        var title: String {
            switch self {
            case .free: "Free"
            case .blockedEnds: "Vietnamese"
            }
        }
    }

    /// Board side: a big 100×100 sheet, like playing on an exercise-book page.
    static let boardSize = 100
    /// Stones in a row needed to win.
    static let winLength = 5

    var size = CaroConfig.boardSize
    var rule: Rule = .blockedEnds

    var cellCount: Int { size * size }
}

/// Game engine for Caro (Vietnamese gomoku). Pure logic — no SwiftUI.
///
/// Turn-based, so there's no race to referee: each device validates and applies its
/// own move, then mirrors it to the other with `place(at:by:)`. Turns strictly
/// alternate, so both boards stay identical. Rounds alternate who moves first
/// (player 0 = host starts round 0); the series score survives restarts.
@MainActor
@Observable
final class CaroGame {
    static let gameID = "caro"
    static let records = PlayerRecordsStore(gameID: gameID)

    enum Status: Equatable {
        case playing
        case paused
        case finished
    }

    enum Outcome: Equatable {
        case placed
        case won
        case draw
        case ignored
    }

    let config: CaroConfig
    let playerNames: [String]
    /// Owner (player index) of each cell, `nil` when empty.
    private(set) var cells: [Int?]
    /// Cell indices in the order they were played.
    private(set) var moves: [Int] = []
    private(set) var turn: Int
    private(set) var status: Status = .playing
    /// Round number in this series; even rounds are started by player 0.
    private(set) var round: Int
    private(set) var winner: Int?
    /// Cells of the winning line, for highlighting.
    private(set) var winningLine: [Int] = []
    /// Rounds won per player in this series.
    private(set) var score: [Int] = [0, 0]
    private(set) var draws = 0

    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var resumedAt: Date?
    @ObservationIgnored private let records: PlayerRecordsStore

    init(
        config: CaroConfig,
        playerNames: [String] = ["Player 1", "Player 2"],
        round: Int = 0,
        records: PlayerRecordsStore = CaroGame.records,
        now: Date = .now
    ) {
        self.config = config
        self.playerNames = playerNames + (playerNames.count..<max(playerNames.count, 2)).map { "Player \($0 + 1)" }
        self.cells = Array(repeating: nil, count: config.cellCount)
        self.round = round
        self.turn = round % 2
        self.records = records
        self.resumedAt = now
    }

    /// The player who moved first this round plays X; the other plays O.
    var startingPlayer: Int { round % 2 }
    var lastMove: Int? { moves.last }

    func mark(of player: Int) -> String { player == startingPlayer ? "X" : "O" }

    func elapsed(at now: Date = .now) -> TimeInterval {
        accumulated + (resumedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    /// Places `player`'s stone. Used for local taps and for mirroring the partner's move.
    /// A move that arrives while paused is still applied, so the devices never diverge.
    @discardableResult
    func place(at index: Int, by player: Int, at now: Date = .now) -> Outcome {
        guard status != .finished, player == turn, cells.indices.contains(index), cells[index] == nil else {
            return .ignored
        }
        cells[index] = player
        moves.append(index)

        if let line = winningLine(through: index, for: player) {
            winningLine = line
            finish(winner: player, at: now)
            return .won
        }
        if moves.count == cells.count {
            finish(winner: nil, at: now)
            return .draw
        }
        turn = 1 - player
        return .placed
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

    /// Next round (or a specific one, as sent by the partner): fresh board, the other
    /// player starts. Rounds only move forward, so a duplicate restart is ignored.
    func restart(round newRound: Int? = nil, at now: Date = .now) {
        let next = newRound ?? round + 1
        guard next > round else { return }
        round = next
        cells = Array(repeating: nil, count: config.cellCount)
        moves = []
        turn = startingPlayer
        winner = nil
        winningLine = []
        accumulated = 0
        resumedAt = now
        status = .playing
    }

    // MARK: Private

    private func finish(winner: Int?, at now: Date) {
        accumulated = elapsed(at: now)
        resumedAt = nil
        self.winner = winner
        status = .finished
        if let winner { score[winner] += 1 } else { draws += 1 }

        let time = accumulated
        for (index, name) in playerNames.prefix(2).enumerated() {
            records.update(name) { record in
                record.games += 1
                record.duels += 1
                if index == winner { record.wins += 1 }
                record.time += time
            }
        }
    }

    /// The five-or-more line through `index`, if it wins under the current rule.
    private func winningLine(through index: Int, for player: Int) -> [Int]? {
        let size = config.size
        let row = index / size, column = index % size
        for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
            var line = [index]
            var forward = (row + dr, column + dc)
            while owner(forward.0, forward.1) == player {
                line.append(forward.0 * size + forward.1)
                forward = (forward.0 + dr, forward.1 + dc)
            }
            var backward = (row - dr, column - dc)
            while owner(backward.0, backward.1) == player {
                line.insert(backward.0 * size + backward.1, at: 0)
                backward = (backward.0 - dr, backward.1 - dc)
            }
            guard line.count >= CaroConfig.winLength else { continue }
            if config.rule == .blockedEnds {
                // Board edges don't count as blocks — only the opponent's stones do.
                let opponent = 1 - player
                if owner(forward.0, forward.1) == opponent && owner(backward.0, backward.1) == opponent { continue }
            }
            return line
        }
        return nil
    }

    private func owner(_ row: Int, _ column: Int) -> Int? {
        let size = config.size
        guard (0..<size).contains(row), (0..<size).contains(column) else { return nil }
        return cells[row * size + column]
    }
}

/// Everything both devices need to start the same Caro series.
/// Player 0 is always the host, player 1 the guest.
struct CaroMatch: Hashable, Codable {
    var config: CaroConfig
    var playerNames: [String]
    /// Which player this device controls (differs per device).
    var localPlayer: Int

    var isHost: Bool { localPlayer == 0 }
}

/// Caro network protocol. Turn-based: each side sends its own `move`, the other mirrors it.
enum CaroMessage: Codable, Equatable {
    /// Host → guest: start a series with these settings.
    case start(CaroMatch)
    /// Either way: the sender placed a stone at `index`.
    case move(index: Int)
    case pause
    case resume
    /// Either way: start round `round` (both sides land on the same round).
    case restart(round: Int)
    /// Either way: the sender left the game screen.
    case leave
}
