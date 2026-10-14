import Foundation
import Testing
@testable import PwL

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "PwLTests.\(UUID().uuidString)")!
}

private func freshRecords() -> PlayerRecordsStore {
    PlayerRecordsStore(gameID: "test", defaults: freshDefaults())
}

struct BoardGeneratorTests {
    @Test(arguments: [5, 50, 100, 150, 200, 377, 500])
    func boardContainsEveryNumberOnceInUniqueCells(count: Int) {
        var rng = SeededGenerator(seed: UInt64(count))
        let board = FindNumbersBoardGenerator.make(
            config: FindNumbersConfig(count: count),
            paletteCount: 7,
            using: &rng
        )

        #expect(board.tiles.count == count)
        #expect(Set(board.tiles.map(\.value)) == Set(1...count))
        #expect(board.columns * board.rows >= count)

        let cells = board.tiles.map { $0.row * board.columns + $0.column }
        #expect(Set(cells).count == count)
        #expect(board.tiles.allSatisfy { (0..<board.columns).contains($0.column) && (0..<board.rows).contains($0.row) })
        #expect(board.tiles.allSatisfy { (0..<7).contains($0.colorIndex) })
    }

    @Test
    func sizeStyleControlsScale() {
        var rng = SeededGenerator(seed: 1)
        let small = FindNumbersBoardGenerator.make(
            config: FindNumbersConfig(count: 200, sizeStyle: .small), paletteCount: 1, using: &rng)
        let big = FindNumbersBoardGenerator.make(
            config: FindNumbersConfig(count: 200, sizeStyle: .big), paletteCount: 1, using: &rng)

        #expect(small.tiles.allSatisfy { FindNumbersConfig.SizeStyle.small.scaleRange.contains($0.scale) })
        #expect(big.tiles.allSatisfy { FindNumbersConfig.SizeStyle.big.scaleRange.contains($0.scale) })
    }
}

@MainActor
struct FindNumbersGameTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test
    func ascendingOrderRequiresOneThenTwo() {
        let game = FindNumbersGame(config: FindNumbersConfig(count: 10), records: freshRecords(), now: start)
        #expect(game.target == 1)
        #expect(game.tap(2, at: start) == .wrong)
        #expect(game.mistakes == 1)
        #expect(game.tap(1, at: start.addingTimeInterval(1)) == .correct)
        #expect(game.target == 2)
        #expect(game.tap(1, at: start.addingTimeInterval(1)) == .ignored)
    }

    @Test
    func fiveMissesInARowBlockForTenSeconds() {
        let game = FindNumbersGame(config: FindNumbersConfig(count: 10), records: freshRecords(), now: start)
        var t: TimeInterval = 0
        for _ in 0..<4 {
            #expect(game.tap(2, at: start.addingTimeInterval(t)) == .wrong)
            t += 1
        }
        #expect(game.blockRemaining(for: 0, at: start.addingTimeInterval(t)) == 0)

        #expect(game.tap(2, at: start.addingTimeInterval(t)) == .wrong) // 5th in a row
        #expect(game.mistakes == 5)
        #expect(game.blockRemaining(for: 0, at: start.addingTimeInterval(t)) == FindNumbersGame.missBlock)
        #expect(game.tap(1, at: start.addingTimeInterval(t + 9)) == .ignored)
        #expect(game.tap(1, at: start.addingTimeInterval(t + 10)) == .correct)
        #expect(game.blockedUntil[0] == nil)
    }

    @Test
    func findingANumberResetsTheMissStreak() {
        let game = FindNumbersGame(config: FindNumbersConfig(count: 10), records: freshRecords(), now: start)
        for i in 0..<4 { game.tap(5, at: start.addingTimeInterval(Double(i))) }
        game.tap(1, at: start.addingTimeInterval(4))
        #expect(game.missStreak[0] == 0)
        #expect(game.tap(5, at: start.addingTimeInterval(5)) == .wrong)
        #expect(game.blockRemaining(for: 0, at: start.addingTimeInterval(5)) == 0)
    }

    @Test
    func pausingFreezesTheBlock() {
        let game = FindNumbersGame(config: FindNumbersConfig(count: 10), records: freshRecords(), now: start)
        for i in 0..<5 { game.tap(5, at: start.addingTimeInterval(Double(i))) }
        game.pause(at: start.addingTimeInterval(6))   // 8s left
        game.resume(at: start.addingTimeInterval(60))
        #expect(game.blockRemaining(for: 0, at: start.addingTimeInterval(60)) == 8)
    }

    @Test
    func descendingOrderStartsFromMax() {
        let game = FindNumbersGame(
            config: FindNumbersConfig(count: 10, order: .descending), records: freshRecords(), now: start)
        #expect(game.target == 10)
        #expect(game.tap(10, at: start) == .correct)
        #expect(game.target == 9)
    }

    @Test
    func finishingFreezesTheClockAndIgnoresTaps() {
        let game = FindNumbersGame(config: FindNumbersConfig(count: 3), records: freshRecords(), now: start)
        game.tap(1, at: start)
        game.tap(2, at: start)
        #expect(game.tap(3, at: start.addingTimeInterval(12)) == .finished)

        #expect(game.status == .finished)
        #expect(game.result?.time == 12)
        #expect(game.elapsed(at: start.addingTimeInterval(60)) == 12)
        #expect(game.tap(1, at: start) == .ignored)
    }

    @Test
    func pausedTimeIsNotCounted() {
        let game = FindNumbersGame(config: FindNumbersConfig(count: 5), records: freshRecords(), now: start)
        game.pause(at: start.addingTimeInterval(5))
        #expect(game.tap(1, at: start.addingTimeInterval(6)) == .ignored)
        game.resume(at: start.addingTimeInterval(65))
        #expect(game.elapsed(at: start.addingTimeInterval(70)) == 10)
    }

    @Test
    func restartResetsProgress() {
        let game = FindNumbersGame(config: FindNumbersConfig(count: 5), records: freshRecords(), now: start)
        game.tap(1, at: start)
        game.tap(3, at: start)
        game.restart(at: start.addingTimeInterval(30))

        #expect(game.foundCount == 0)
        #expect(game.mistakes == 0)
        #expect(game.status == .playing)
        #expect(game.elapsed(at: start.addingTimeInterval(31)) == 1)
    }

    @Test
    func randomOrderCoversEveryNumberOnce() {
        let game = FindNumbersGame(
            config: FindNumbersConfig(count: 40, order: .random), records: freshRecords(), now: start)
        #expect(game.sequence.sorted() == Array(1...40))
        while let target = game.target {
            #expect(game.tap(target, at: start) != .wrong)
        }
        #expect(game.status == .finished)
    }

    @Test
    func duelFirstClaimWinsTheNumber() {
        let game = FindNumbersGame(
            config: FindNumbersConfig(count: 4), playerNames: ["Khoa", "Linh"], records: freshRecords(), now: start)

        let event = game.claim(1, by: 1, at: start.addingTimeInterval(2))
        #expect(event == FindNumbersGame.FindEvent(value: 1, player: 1, reaction: 2))
        // Host's own late tap on the same number is ignored.
        #expect(game.claim(1, by: 0, at: start.addingTimeInterval(2.1)) == nil)
        #expect(game.tap(2, by: 0, at: start.addingTimeInterval(3)) == .correct)

        #expect(game.foundBy == [1: 1, 2: 0])
        #expect(game.players[0].found == 1)
        #expect(game.players[0].time == 1)
        #expect(game.players[1].found == 1)
    }

    @Test
    func duelWrongTapLocksOnlyThatPlayer() {
        let game = FindNumbersGame(
            config: FindNumbersConfig(count: 5), records: freshRecords(), now: start)

        #expect(game.check(3, by: 0, at: start) == .wrong)
        #expect(game.check(1, by: 0, at: start.addingTimeInterval(0.5)) == .ignored)
        #expect(game.check(1, by: 1, at: start.addingTimeInterval(0.5)) == .correct)
        #expect(game.check(1, by: 0, at: start.addingTimeInterval(1)) == .correct)
        #expect(game.players[0].mistakes == 1)
    }

    @Test
    func sameSeedBuildsIdenticalGamesOnBothDevices() {
        let config = FindNumbersConfig(count: 120, order: .random)
        let host = FindNumbersGame(config: config, records: freshRecords(), seed: 42, now: start)
        let guest = FindNumbersGame(config: config, records: freshRecords(), seed: 42, now: start)
        #expect(host.board == guest.board)
        #expect(host.sequence == guest.sequence)

        host.restart(seed: 7, at: start)
        guest.restart(seed: 7, at: start)
        #expect(host.board == guest.board)
        #expect(host.sequence == guest.sequence)
    }

    @Test
    func guestMirrorsHostDecisionsAndFinishesWithSameResult() {
        let config = FindNumbersConfig(count: 3)
        let names = ["Khoa", "Linh"]
        let host = FindNumbersGame(config: config, playerNames: names, records: freshRecords(), seed: 1, now: start)
        let guest = FindNumbersGame(config: config, playerNames: names, records: freshRecords(), seed: 1, now: start)

        // Guest taps a wrong number: recorded locally, mirrored on host.
        #expect(guest.check(2, by: 1, at: start) == .wrong)
        host.applyMistake(by: 1)

        // Guest claims 1, host referees, guest applies the result.
        #expect(guest.check(1, by: 1, at: start.addingTimeInterval(1)) == .correct)
        let first = host.claim(1, by: 1, at: start.addingTimeInterval(1))!
        guest.applyFound(first, at: start.addingTimeInterval(1))

        // Host finds 2 and 3.
        for (value, offset) in [(2, 2.0), (3, 3.0)] {
            let event = host.claim(value, by: 0, at: start.addingTimeInterval(offset))!
            guest.applyFound(event, at: start.addingTimeInterval(offset))
        }

        #expect(host.status == .finished)
        #expect(guest.status == .finished)
        #expect(host.result?.players == guest.result?.players)
        #expect(host.result?.winnerIndex == 0)
        #expect(guest.result?.winnerIndex == 0)
    }

    @Test
    func duelWinnerIsMostPointsThenFewestMistakes() {
        typealias Stats = FindNumbersGame.PlayerStats
        #expect(FindNumbersGame.winner(of: [Stats(name: "A", found: 3), Stats(name: "B", found: 5)]) == 1)
        #expect(FindNumbersGame.winner(of: [Stats(name: "A", found: 4, mistakes: 1), Stats(name: "B", found: 4, mistakes: 2)]) == 0)
        #expect(FindNumbersGame.winner(of: [Stats(name: "A", found: 4, time: 8), Stats(name: "B", found: 4, time: 6)]) == 1)
        #expect(FindNumbersGame.winner(of: [Stats(name: "A", found: 4, time: 6), Stats(name: "B", found: 4, time: 6)]) == nil)
    }

    @Test
    func duelResultIsSavedToScoreboard() {
        let records = freshRecords()
        let game = FindNumbersGame(
            config: FindNumbersConfig(count: 2), playerNames: ["Khoa", "Linh"],
            records: records, now: start)
        game.claim(1, by: 1, at: start.addingTimeInterval(1))
        game.claim(2, by: 1, at: start.addingTimeInterval(2))

        #expect(records.record(for: "Linh").wins == 1)
        #expect(records.record(for: "Linh").found == 2)
        #expect(records.record(for: "Khoa").duels == 1)
        #expect(records.record(for: "Khoa").wins == 0)
    }

    @Test
    func matchMessagesRoundTrip() throws {
        let match = FindNumbersMatch(
            config: FindNumbersConfig(count: 150, order: .random), seed: .max,
            playerNames: ["Khoa", "Linh"], localPlayer: 0)
        let messages: [FindNumbersMessage] = [
            .start(match), .claim(value: 12), .found(.init(value: 12, player: 1, reaction: 1.5)),
            .mistake(player: 0), .pause, .resume, .restart(seed: 99), .leave,
        ]
        for message in messages {
            let data = try JSONEncoder().encode(message)
            #expect(try JSONDecoder().decode(FindNumbersMessage.self, from: data) == message)
        }
    }
}
