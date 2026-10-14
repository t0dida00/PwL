import CoreGraphics
import Foundation
import Testing
@testable import PwL

private func records() -> PlayerRecordsStore {
    PlayerRecordsStore(gameID: "test", defaults: UserDefaults(suiteName: "PwLTests.\(UUID().uuidString)")!)
}

struct SeekItLayoutTests {
    @Test
    func sixRoomsAllEquallyHard() {
        let levels = SeekItLevel.all
        #expect(levels.count == 6)
        #expect(Set(levels.map(\.scene)).count == 6) // one room each
        for level in levels {
            #expect(level.objectCount == 50 && level.targetCount == 10 && level.hints == 2)
            #expect(level.baseSize == levels[0].baseSize && level.spacing == levels[0].spacing)
            #expect(level.hasOccluders)
        }
    }

    @Test(arguments: SeekItLevel.all.map(\.number))
    func everyLevelFillsItsRoom(number: Int) {
        let level = SeekItLevel(number)
        var rng = SeededGenerator(seed: 99)
        let layout = SeekItLayout.make(scene: level.scene.scene, level: level, using: &rng)
        #expect(layout.targets.count == level.targetCount)
        let targets = layout.targets.compactMap(layout.placement)
        #expect(targets.allSatisfy { !$0.name.isEmpty && $0.isTarget })
        #expect(Set(targets.map(\.emoji)).count == targets.count) // every shape is unique
        #expect(layout.placements.count == 50, "level \(number): \(layout.placements.count)")
        #expect(layout.placements.allSatisfy { (0...SeekItCanvas.width).contains($0.center.x) && (0...SeekItCanvas.height).contains($0.center.y) })
    }

    @Test(arguments: SeekItLevel.all.map(\.number))
    func roomsHideTwentyObjectsThatOverlap(number: Int) {
        let level = SeekItLevel(number)
        var rng = SeededGenerator(seed: 21)
        let layout = SeekItLayout.make(scene: level.scene.scene, level: level, using: &rng)
        #expect(layout.targets.count == 10)
        #expect(layout.placements.count == 50, "level \(number): \(layout.placements.count)")
        #expect(Set(layout.placements.map(\.emoji)).count == layout.placements.count, "duplicates in level \(number)")
        let items = layout.placements
        var overlapping = 0
        for i in items.indices {
            for j in items.indices where j > i {
                let d = hypot(items[i].center.x - items[j].center.x, items[i].center.y - items[j].center.y)
                let reach = (items[i].size + items[j].size) / 2
                #expect(d >= reach * level.spacing * 0.999) // never stacked right on top
                if d < reach { overlapping += 1 }
            }
        }
        #expect(overlapping >= 15, "level \(number) only has \(overlapping) overlapping pairs")
    }

    @Test
    func roomsNeverRepeatAnObjectAcrossManySeeds() {
        for seed in 0..<15 {
            for level in SeekItLevel.all {
                var rng = SeededGenerator(seed: UInt64(seed))
                let layout = SeekItLayout.make(scene: level.scene.scene, level: level, using: &rng)
                #expect(layout.placements.count == 50, "seed \(seed) level \(level.number)")
                #expect(Set(layout.placements.map(\.emoji)).count == 50, "seed \(seed) level \(level.number)")
                #expect(layout.targets.count == 10)
            }
        }
    }

    @Test
    func targetsAreSpreadOutAcrossTheRoom() {
        for seed in 0..<15 {
            for level in SeekItLevel.all {
                var rng = SeededGenerator(seed: UInt64(seed))
                let layout = SeekItLayout.make(scene: level.scene.scene, level: level, using: &rng)
                let targets = layout.targets.compactMap(layout.placement)
                var closest = CGFloat.infinity
                for (i, a) in targets.enumerated() {
                    for b in targets[(i + 1)...] {
                        closest = min(closest, hypot(a.center.x - b.center.x, a.center.y - b.center.y))
                    }
                }
                #expect(closest >= 150, "seed \(seed) level \(level.number): targets only \(Int(closest)) apart")
            }
        }
    }

    @Test
    func sameSeedSameRoom() {
        var a = SeededGenerator(seed: 5), b = SeededGenerator(seed: 5)
        let first = SeekItLayout.make(scene: SeekItScene.attic, level: SeekItLevel(5), using: &a)
        let second = SeekItLayout.make(scene: SeekItScene.attic, level: SeekItLevel(5), using: &b)
        #expect(first.placements == second.placements)
        #expect(first.targets == second.targets)
    }

    @Test
    func objectsOnlySitOnSurfacesTheyAllow() {
        for scene in SeekItSceneID.allCases {
            var rng = SeededGenerator(seed: 3)
            let layout = SeekItLayout.make(scene: scene.scene, level: SeekItLevel(3), using: &rng)
            for placement in layout.placements {
                guard let item = scene.scene.pool.first(where: { $0.emoji == placement.emoji }) else { continue } // odds and ends
                let fits = scene.scene.regions.contains { region in
                    item.surfaces.contains(region.surface)
                        && region.rect.insetBy(dx: -1, dy: -placement.size).contains(placement.center)
                }
                #expect(fits, "\(placement.emoji) in \(scene)")
            }
        }
    }
}

@MainActor
struct SeekItGameTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func game(seed: UInt64 = 1, level: Int = 1) -> SeekItGame {
        SeekItGame(playerNames: ["Khoa", "Linh"], records: records(), seed: seed, startLevel: level, now: start)
    }

    private func target(_ game: SeekItGame, _ index: Int = 0) -> SeekItPlacement {
        game.layout.placement(game.layout.targets[index])!
    }

    /// A point well away from every object.
    private func emptyPoint(_ game: SeekItGame) -> CGPoint {
        for y in stride(from: 10.0, to: 800, by: 20) {
            for x in stride(from: 10.0, to: 1800, by: 20) {
                if game.layout.placements.allSatisfy({ hypot($0.center.x - x, $0.center.y - y) > $0.size * 1.5 + 40 }) {
                    return CGPoint(x: x, y: y)
                }
            }
        }
        return CGPoint(x: 5, y: 5)
    }

    @Test
    func startsInTheKitchenAtLevelOne() {
        let g = game()
        #expect(g.level.number == 1)
        #expect(g.sceneID == .kitchen)
        #expect(g.targetCount == 10)
        #expect(g.hintsLeft == [2, 2])
    }

    @Test
    func tappingATargetHitsItAndNearbyCountsWithTolerance() {
        let g = game()
        let t = target(g)
        #expect(g.check(t.center, by: 0, at: start) == .hit(t.id))
        #expect(g.check(CGPoint(x: t.center.x + t.size / 2, y: t.center.y), by: 0, at: start) == .hit(t.id))
    }

    @Test
    func missesLockOutThenBlockAfterFiveInARow() {
        let g = game()
        let empty = emptyPoint(g)
        var t: TimeInterval = 0
        for _ in 0..<4 {
            #expect(g.check(empty, by: 0, at: start.addingTimeInterval(t)) == .miss)
            #expect(g.check(empty, by: 0, at: start.addingTimeInterval(t + 0.3)) == .ignored)
            t += 1
        }
        #expect(g.check(empty, by: 0, at: start.addingTimeInterval(t)) == .miss)
        #expect(g.blockRemaining(for: 0, at: start.addingTimeInterval(t)) == SeekItGame.missBlock)
        #expect(g.check(target(g).center, by: 0, at: start.addingTimeInterval(t + 9)) == .ignored)
    }

    @Test
    func firstClaimWinsAndFoundObjectsAreHarmless() {
        let g = game()
        let t = target(g)
        #expect(g.claim(t.id, by: 1, at: start.addingTimeInterval(2)) != nil)
        #expect(g.claim(t.id, by: 0, at: start.addingTimeInterval(2)) == nil)
        #expect(g.players.map(\.found) == [0, 1])
        #expect(g.check(t.center, by: 0, at: start.addingTimeInterval(3)) != .miss)
    }

    @Test
    func clearingARoomOpensTheNextLevel() {
        let g = game()
        for id in g.layout.targets { g.claim(id, by: 0) }
        #expect(g.level.number == 2)
        #expect(g.sceneID == .livingRoom)
        #expect(g.foundCount == 0)
        #expect(g.players[0].found == 10)         // carries over
        #expect(g.status == .playing)
        // A late claim from level 1 doesn't land in level 2.
        #expect(g.claim(g.layout.targets[0], by: 1, level: 1) == nil)
    }

    @Test
    func guestMirrorsHostThroughTheWholeJourney() {
        let host = game(seed: 8), guest = game(seed: 8)
        var turn = 0
        while host.status != .finished {
            #expect(host.layout.targets == guest.layout.targets)
            let id = host.layout.targets.first { host.foundBy[$0] == nil }!
            let event = host.claim(id, by: turn % 2, level: host.level.number, at: start.addingTimeInterval(Double(turn + 1)))!
            guest.applyFound(event, at: start.addingTimeInterval(Double(turn + 1)))
            turn += 1
        }
        let total = SeekItLevel.all.map(\.targetCount).reduce(0, +)
        #expect(turn == total)
        #expect(guest.status == .finished)
        #expect(host.result?.players.map(\.found).reduce(0, +) == total)
        #expect(guest.result?.players.map(\.found) == host.result?.players.map(\.found))
    }

    @Test
    func bothPlayersGetTheSameMapOnEveryLevelAndAfterRestart() {
        let host = game(seed: 2024), guest = game(seed: 2024)
        func sameRoom() {
            #expect(host.level == guest.level)
            #expect(host.layout.placements == guest.layout.placements)
            #expect(host.layout.targets == guest.layout.targets)
        }
        sameRoom()
        while host.status != .finished {
            let id = host.layout.targets.first { host.foundBy[$0] == nil }!
            guest.applyFound(host.claim(id, by: 0, level: host.level.number)!)
            sameRoom()
        }
        host.restart(seed: 99)
        guest.restart(seed: 99)
        sameRoom()
    }

    @Test
    func hintsAreLimitedPerLevelAndPointAtOpenTargets() {
        let g = game(level: 3)
        #expect(g.useHint(by: 0) == g.layout.targets[0])
        g.claim(g.layout.targets[0], by: 1)
        #expect(g.useHint(by: 0) == g.layout.targets[1])
        #expect(g.useHint(by: 0) == nil) // 2 hints per room
        #expect(g.hintsLeft == [0, 2])
    }

    @Test
    func restartGoesBackToLevelOne() {
        let g = game(level: 4)
        g.claim(g.layout.targets[0], by: 0)
        g.restart(seed: 77, at: start)
        #expect(g.level.number == 1)
        #expect(g.foundCount == 0)
        #expect(g.players.map(\.found) == [0, 0])
        #expect(g.hintsLeft == [2, 2])
    }

    @Test
    func winnerRanking() {
        typealias Stats = SeekItGame.PlayerStats
        #expect(SeekItGame.winner(of: [Stats(name: "A", found: 4), Stats(name: "B", found: 2)]) == 0)
        #expect(SeekItGame.winner(of: [Stats(name: "A", found: 3, mistakes: 2), Stats(name: "B", found: 3, mistakes: 1)]) == 1)
        #expect(SeekItGame.winner(of: [Stats(name: "A", found: 3, time: 9), Stats(name: "B", found: 3, time: 12)]) == 0)
        #expect(SeekItGame.winner(of: [Stats(name: "A", found: 3), Stats(name: "B", found: 3)]) == nil)
    }

    @Test
    func messagesRoundTrip() throws {
        let match = SeekItMatch(seed: 4, playerNames: ["A", "B"], localPlayer: 0)
        let messages: [SeekItMessage] = [
            .start(match), .claim(id: 3, level: 2), .found(.init(id: 3, player: 1, reaction: 2.5, level: 2)),
            .mistake(player: 0), .pause, .resume, .restart(seed: 9), .leave,
        ]
        for message in messages {
            #expect(try JSONDecoder().decode(SeekItMessage.self, from: JSONEncoder().encode(message)) == message)
        }
    }
}
