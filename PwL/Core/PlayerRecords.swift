import Foundation

/// Lifetime metrics for one player in one game.
struct PlayerRecord: Codable, Equatable {
    var games = 0
    var duels = 0
    var wins = 0
    var found = 0
    var mistakes = 0
    var time: TimeInterval = 0
    var fastestFind: TimeInterval?

    var averageFind: TimeInterval? { found > 0 ? time / Double(found) : nil }
    var winRate: Double? { duels > 0 ? Double(wins) / Double(duels) : nil }
    var accuracy: Double? {
        let taps = found + mistakes
        return taps > 0 ? Double(found) / Double(taps) : nil
    }
}

/// Per-player records, keyed by game id + player name.
struct PlayerRecordsStore {
    let gameID: String
    var defaults: UserDefaults = .standard

    func record(for name: String) -> PlayerRecord {
        guard let data = defaults.data(forKey: key(name)),
              let record = try? JSONDecoder().decode(PlayerRecord.self, from: data) else { return PlayerRecord() }
        return record
    }

    func update(_ name: String, _ change: (inout PlayerRecord) -> Void) {
        var record = record(for: name)
        change(&record)
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: key(name))
        }
    }

    func reset(_ names: [String]) {
        names.forEach { defaults.removeObject(forKey: key($0)) }
    }

    private func key(_ name: String) -> String {
        "records.\(gameID).\(name.lowercased())"
    }
}
