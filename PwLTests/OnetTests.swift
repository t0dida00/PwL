import Foundation
import Testing
@testable import PwL

/// "A.B" rows → tiles: letters are faces, "." is empty.
private func grid(_ rows: [String]) -> (tiles: [Int?], rows: Int, columns: Int) {
    let tiles: [Int?] = rows.joined().map { $0 == "." ? nil : Int($0.asciiValue! - Character("A").asciiValue!) }
    return (tiles, rows.count, rows[0].count)
}

/// Pads short rows with "." to the real 9 × 16 board.
private func board(_ rows: [String]) -> [Int?] {
    let full = (0..<OnetConfig.rows).map { r in
        let row = r < rows.count ? rows[r] : ""
        return row + String(repeating: ".", count: OnetConfig.columns - row.count)
    }
    return grid(full).tiles
}

private func path(_ rows: [String], _ a: (Int, Int), _ b: (Int, Int)) -> [OnetPoint]? {
    let g = grid(rows)
    return OnetGame.path(from: a.0 * g.columns + a.1, to: b.0 * g.columns + b.1, in: g.tiles, rows: g.rows, columns: g.columns)
}

struct OnetPathTests {
    @Test
    func neighboursAndStraightLines() {
        #expect(path(["AA"], (0, 0), (0, 1))?.count == 2)
        #expect(path(["A.A"], (0, 0), (0, 2))?.count == 2)
        #expect(path(["ABA", "CCC"], (0, 0), (0, 2))?.count == 4) // around the top edge
    }

    @Test
    func oneAndTwoTurns() {
        // One turn: A(0,0) → (0,1) corner → down to A(1,1).
        #expect(path(["A.", "BA"], (0, 0), (1, 1))?.count == 3)
        // Two turns down the empty middle column.
        #expect(path(["A.B", "B.B", "B.A"], (0, 0), (2, 2))?.count == 4)
    }

    @Test
    func differentFacesOrTooManyTurnsDontLink() {
        #expect(path(["AB"], (0, 0), (0, 1)) == nil)
        // Enclosed: the only route needs three turns.
        let rows = [
            "CCCCC",
            "CA.CC",
            "CCC.C",
            "CC.AC",
            "CCCCC",
        ]
        #expect(path(rows, (1, 1), (3, 3)) == nil)
    }

    @Test
    func pathsCanUseTheOuterRing() {
        // Both A's on the left edge, separated by B: go out to column -1.
        let corners = path(["A", "B", "A"], (0, 0), (2, 0))
        #expect(corners?.contains(OnetPoint(row: 0, column: -1)) == true || corners?.contains(OnetPoint(row: 0, column: 1)) == true)
        #expect(corners?.count == 4)
    }
}

@MainActor
struct OnetGameTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func records() -> PlayerRecordsStore {
        PlayerRecordsStore(gameID: "test", defaults: UserDefaults(suiteName: "PwLTests.\(UUID().uuidString)")!)
    }

    @Test(arguments: [1, 7, 42, 2024])
    func generatedBoardIsEveryFlagFourTimesAndPlayable(seed: UInt64) {
        var rng = SeededGenerator(seed: seed)
        let tiles = OnetBoardGenerator.make(config: OnetConfig(), using: &rng)
        #expect(tiles.count == 144)
        var counts: [Int: Int] = [:]
        tiles.forEach { counts[$0!, default: 0] += 1 }
        #expect(counts.count == 36)
        #expect(counts.values.allSatisfy { $0 == 4 })
        #expect(OnetGame.hasMove(in: tiles, rows: 9, columns: 16))
    }

    @Test
    func sameSeedSameBoard() {
        let a = OnetGame(config: OnetConfig(), records: records(), seed: 42, now: start)
        let b = OnetGame(config: OnetConfig(), records: records(), seed: 42, now: start)
        #expect(a.tiles == b.tiles)
    }

    @Test
    func wrongPickIsAMistakeWithLockout() {
        let game = OnetGame(config: OnetConfig(), records: records(), layout: board(["ABA", "B"]), now: start)
        #expect(game.check(0, 1, by: 0, at: start) == .wrong)
        #expect(game.players[0].mistakes == 1)
        #expect(game.check(0, 2, by: 0, at: start.addingTimeInterval(0.3)) == .ignored) // locked
        if case .match = game.check(0, 2, by: 0, at: start.addingTimeInterval(1)) {} else {
            Issue.record("A's on the top row should link over the edge")
        }
    }

    @Test
    func firstClaimWinsTheRace() {
        let game = OnetGame(config: OnetConfig(), records: records(), seed: 3, now: start)
        let (a, b) = firstLinkablePair(game)
        #expect(game.claim(a, b, by: 1) != nil)
        #expect(game.claim(a, b, by: 0) == nil)
        #expect(game.players.map(\.pairs) == [0, 1])
        #expect(game.tiles[a] == nil && game.tiles[b] == nil)
        #expect(game.lastMatch?.event.player == 1)
    }

    @Test
    func guestMirrorsHostAndBothFinishTheSame() {
        let config = OnetConfig(levels: .one)
        let host = OnetGame(config: config, playerNames: ["Khoa", "Linh"], records: records(), seed: 11, now: start)
        let guest = OnetGame(config: config, playerNames: ["Khoa", "Linh"], records: records(), seed: 11, now: start)
        var turn = 0
        while host.status != .finished {
            let (a, b) = firstLinkablePair(host)
            let event = host.claim(a, b, by: turn % 2)!
            guest.applyMatch(event)
            #expect(host.tiles == guest.tiles)        // incl. identical reshuffles
            turn += 1
        }
        #expect(guest.status == .finished)
        #expect(host.shuffleCount == guest.shuffleCount)
        #expect(host.result?.players.map(\.pairs) == [36, 36])
        #expect(host.result?.winnerIndex == nil)
    }

    @Test
    func stuckBoardReshuffles() {
        // An A/B checker in a corner can't be linked within two turns.
        let game = OnetGame(config: OnetConfig(), records: records(), seed: 5, layout: board(["AB", "BA", "", "C", "", "C"]), now: start)
        #expect(game.path(from: 0, to: 17) == nil)
        #expect(game.path(from: 1, to: 16) == nil)

        #expect(game.claim(48, 80, by: 0) != nil) // the C's; only the stuck checker is left
        #expect(game.shuffleCount > 0)
        #expect(game.pairsLeft == 2)
        #expect(OnetGame.hasMove(in: game.tiles, rows: 9, columns: 16))
    }

    @Test(arguments: [
        (OnetLevel.fallDown, ["A.", "..", ".B"], ["..", "..", "AB"]),
        (OnetLevel.floatUp, ["A.", "..", ".B"], ["AB", "..", ".."]),
        (OnetLevel.slideLeft, [".A.B"], ["AB.."]),
        (OnetLevel.slideRight, ["A.B."], ["..AB"]),
        (OnetLevel.squeezeIn, ["A..B"], [".AB."]),
        (OnetLevel.splitApart, [".AB."], ["A..B"]),
        (OnetLevel.squash, ["A", ".", ".", "B"], [".", "A", "B", "."]),
        (OnetLevel.spreadOut, [".", "A", "B", "."], ["A", ".", ".", "B"]),
    ])
    func levelLinesCompactTilesTheRightWay(level: OnetLevel, before: [String], after: [String]) {
        var tiles = grid(before).tiles
        let g = grid(before)
        for line in level.lines(rows: g.rows, columns: g.columns) {
            let kept = line.compactMap { tiles[$0] }
            for (offset, cell) in line.enumerated() { tiles[cell] = offset < kept.count ? kept[offset] : nil }
        }
        #expect(tiles == grid(after).tiles)
    }

    @Test
    func tilesSlideAfterMatchesAndKeepTheirIdentity() {
        // Level 2 (fall down) on a 1-level-per-board run of 3 levels.
        let config = OnetConfig(levels: .three)
        let host = OnetGame(config: config, records: records(), seed: 8, now: start)
        let guest = OnetGame(config: config, records: records(), seed: 8, now: start)
        // Clear level 1.
        while host.level == .classic {
            let (a, b) = firstLinkablePair(host)
            guest.applyMatch(host.claim(a, b, by: 0)!)
        }
        #expect(host.level == .fallDown && guest.level == .fallDown)
        #expect(host.tiles == guest.tiles)
        #expect(host.pairsLeft == OnetConfig.pairs)

        let (a, b) = firstLinkablePair(host)
        guest.applyMatch(host.claim(a, b, by: 1)!)
        #expect(host.tiles == guest.tiles && host.tileIDs == guest.tileIDs)
        // Gravity: no empty cell sits below a tile in any column.
        for column in 0..<16 {
            let cells = (0..<9).map { host.tiles[$0 * 16 + column] }
            if let firstTile = cells.firstIndex(where: { $0 != nil }) {
                #expect(cells[firstTile...].allSatisfy { $0 != nil })
            }
        }
        #expect(Set(host.tileIDs.compactMap { $0 }).count == host.pairsLeft * 2)
    }

    @Test
    func staleClaimsAreRejectedOnlyOnSlidingLevels() {
        let classic = OnetGame(config: OnetConfig(), records: records(), seed: 4, now: start)
        let (a, b) = firstLinkablePair(classic)
        let seen = classic.revision
        let (c, d) = firstLinkablePair(classic, excluding: [a, b])
        classic.claim(c, d, by: 0)
        #expect(classic.claim(a, b, by: 1, revision: seen) != nil) // nothing moved on level 1
    }

    @Test
    func finishingTheLastLevelEndsTheMatchWithTotals() {
        let game = OnetGame(config: OnetConfig(levels: .three), records: records(), seed: 12, now: start)
        var turn = 0
        while game.status != .finished {
            let (a, b) = firstLinkablePair(game)
            game.claim(a, b, by: turn % 2)
            turn += 1
        }
        #expect(game.level == .floatUp)
        #expect(game.result?.players.map(\.pairs).reduce(0, +) == 3 * OnetConfig.pairs)
    }

    @Test
    func winnerRanking() {
        typealias Stats = OnetGame.PlayerStats
        #expect(OnetGame.winner(of: [Stats(name: "A", pairs: 5), Stats(name: "B", pairs: 3)]) == 0)
        #expect(OnetGame.winner(of: [Stats(name: "A", pairs: 4, mistakes: 2), Stats(name: "B", pairs: 4, mistakes: 1)]) == 1)
        #expect(OnetGame.winner(of: [Stats(name: "A", pairs: 4), Stats(name: "B", pairs: 4)]) == nil)
    }

    @Test
    func messagesRoundTrip() throws {
        let match = OnetMatch(config: OnetConfig(), seed: 9, playerNames: ["A", "B"], localPlayer: 0)
        let messages: [OnetMessage] = [
            .start(match), .claim(first: 1, second: 2, revision: 4), .matched(.init(first: 1, second: 2, player: 1)),
            .rejected(first: 1, second: 2), .mistake(player: 0), .pause, .resume, .restart(seed: 3), .leave,
        ]
        for message in messages {
            #expect(try JSONDecoder().decode(OnetMessage.self, from: JSONEncoder().encode(message)) == message)
        }
    }

    private func firstLinkablePair(_ game: OnetGame, excluding: Set<Int> = []) -> (Int, Int) {
        let cells = game.tiles.indices.filter { game.tiles[$0] != nil && !excluding.contains($0) }
        for i in cells {
            for j in cells where j > i && game.path(from: i, to: j) != nil {
                return (i, j)
            }
        }
        Issue.record("No linkable pair")
        return (0, 0)
    }
}
