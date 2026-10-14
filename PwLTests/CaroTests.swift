import Foundation
import Testing
@testable import PwL

@MainActor
struct CaroGameTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func makeGame(size: Int = 15, rule: CaroConfig.Rule = .free, round: Int = 0) -> CaroGame {
        CaroGame(
            config: CaroConfig(size: size, rule: rule),
            playerNames: ["Khoa", "Linh"],
            round: round,
            records: PlayerRecordsStore(gameID: "test", defaults: UserDefaults(suiteName: "PwLTests.\(UUID().uuidString)")!),
            now: start
        )
    }

    /// Plays alternating moves starting with whoever's turn it is.
    @discardableResult
    private func play(_ game: CaroGame, _ cells: [(Int, Int)]) -> CaroGame.Outcome {
        var outcome = CaroGame.Outcome.ignored
        for (row, column) in cells {
            outcome = game.place(at: row * game.config.size + column, by: game.turn)
        }
        return outcome
    }

    @Test
    func turnsAlternateAndCellsCanOnlyBeUsedOnce() {
        let game = makeGame()
        #expect(game.turn == 0)
        #expect(game.mark(of: 0) == "X")
        #expect(game.place(at: 0, by: 1) == .ignored) // not your turn
        #expect(game.place(at: 0, by: 0) == .placed)
        #expect(game.turn == 1)
        #expect(game.place(at: 0, by: 1) == .ignored) // taken
        #expect(game.place(at: 1, by: 1) == .placed)
        #expect(game.moves == [0, 1])
    }

    @Test(arguments: [(0, 1), (1, 0), (1, 1), (1, -1)])
    func fiveInARowWinsInEveryDirection(dr: Int, dc: Int) {
        let game = makeGame()
        var cells: [(Int, Int)] = []
        for i in 0..<5 {
            cells.append((7 + i * dr, 7 + i * dc))                 // X
            if i < 4 { cells.append((0, i * 2)) }                   // O, scattered on the top row
        }
        #expect(play(game, cells) == .won)
        #expect(game.winner == 0)
        #expect(game.winningLine.count == 5)
        #expect(game.status == .finished)
        #expect(game.score == [1, 0])
        #expect(game.place(at: 100, by: game.turn) == .ignored)
    }

    @Test
    func defaultBoardIs100By100AndWinsWorkAtTheFarCorner() {
        let game = CaroGame(
            config: CaroConfig(),
            records: PlayerRecordsStore(gameID: "test", defaults: UserDefaults(suiteName: "PwLTests.\(UUID().uuidString)")!),
            now: start
        )
        #expect(game.config.size == 100)
        #expect(game.cells.count == 10_000)
        let moves = (0..<5).flatMap { i in [(99, 95 + i), (0, i * 2)] }.dropLast()
        #expect(play(game, Array(moves)) == .won)
        #expect(game.winningLine == (95...99).map { 99 * 100 + $0 })
    }

    @Test
    func fourIsNotEnough() {
        let game = makeGame()
        let outcome = play(game, [(7, 7), (0, 0), (7, 8), (0, 2), (7, 9), (0, 4), (7, 10)])
        #expect(outcome == .placed)
        #expect(game.winner == nil)
    }

    @Test
    func vietnameseRuleIgnoresFiveBlockedAtBothEnds() {
        // O . X X X X X . O with O on both ends of X's row.
        let moves: [(Int, Int)] = [
            (7, 3), (7, 2),   // X, O blocks left
            (7, 4), (7, 8),   // X, O blocks right
            (7, 5), (0, 0),
            (7, 6), (0, 2),
            (7, 7),           // fifth X: blocked both ends
        ]
        let blocked = makeGame(rule: .blockedEnds)
        #expect(play(blocked, moves) == .placed)
        #expect(blocked.winner == nil)

        let free = makeGame(rule: .free)
        #expect(play(free, moves) == .won)
    }

    @Test
    func vietnameseRuleAllowsFiveBlockedAtOneEndOrByTheEdge() {
        let oneEnd = makeGame(rule: .blockedEnds)
        #expect(play(oneEnd, [(7, 3), (7, 2), (7, 4), (0, 0), (7, 5), (0, 2), (7, 6), (0, 4), (7, 7)]) == .won)

        let edge = makeGame(rule: .blockedEnds)
        #expect(play(edge, [(0, 0), (0, 5), (0, 1), (5, 5), (0, 2), (6, 6), (0, 3), (8, 8), (0, 4)]) == .won)
    }

    @Test
    func fullBoardIsADraw() {
        let game = makeGame(size: 3)
        let outcome = play(game, (0..<9).map { ($0 / 3, $0 % 3) })
        #expect(outcome == .draw)
        #expect(game.winner == nil)
        #expect(game.draws == 1)
    }

    @Test
    func restartAlternatesStarterKeepsScoreAndIgnoresDuplicates() {
        let game = makeGame()
        play(game, [(7, 7), (0, 0), (7, 8), (0, 2), (7, 9), (0, 4), (7, 10), (0, 6), (7, 11)])
        #expect(game.score == [1, 0])

        game.restart()
        #expect(game.round == 1)
        #expect(game.turn == 1)
        #expect(game.mark(of: 1) == "X")
        #expect(game.moves.isEmpty)
        #expect(game.score == [1, 0])

        game.place(at: 50, by: 1)
        game.restart(round: 1) // partner's restart for the same round arrives late
        #expect(game.moves == [50])
    }

    @Test
    func guestMirrorsHostMoves() {
        let host = makeGame(rule: .blockedEnds)
        let guest = makeGame(rule: .blockedEnds)
        let moves = [(7, 7), (6, 6), (7, 8), (6, 7), (7, 9), (6, 8), (7, 10), (6, 9), (7, 11)]
        for (row, column) in moves {
            let index = row * 15 + column
            let player = host.turn
            #expect(host.place(at: index, by: player) != .ignored)
            #expect(guest.place(at: index, by: player) != .ignored)
        }
        #expect(host.cells == guest.cells)
        #expect(host.winner == 0 && guest.winner == 0)
    }

    @Test
    func pausedMovesStillApplyAndClockFreezes() {
        let game = makeGame()
        game.pause(at: start.addingTimeInterval(10))
        #expect(game.place(at: 0, by: 0) == .placed)
        #expect(game.elapsed(at: start.addingTimeInterval(100)) == 10)
    }

    @Test
    func messagesRoundTrip() throws {
        let match = CaroMatch(config: CaroConfig(size: 20, rule: .free), playerNames: ["A", "B"], localPlayer: 0)
        for message in [CaroMessage.start(match), .move(index: 42), .pause, .resume, .restart(round: 3), .leave] {
            let data = try JSONEncoder().encode(message)
            #expect(try JSONDecoder().decode(CaroMessage.self, from: data) == message)
        }
    }
}
