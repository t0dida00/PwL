import SwiftUI

/// Lifetime duel stats for the couple (its own tab).
struct ScoreboardView: View {
    @Environment(AccountStore.self) private var account
    @State private var records: [PlayerRecord] = []
    @State private var caroRecords: [PlayerRecord] = []
    @State private var onetRecords: [PlayerRecord] = []
    @State private var confirmReset = false

    private var names: [String] { account.playerNames }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("Duel wins")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.plum)
                        .textCase(.uppercase)
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                        winsColumn(0, records)
                        Text("–")
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.inkSoft)
                        winsColumn(1, records)
                    }
                    Text("Find Numbers")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity)
                .card()

                ForEach(records.indices, id: \.self) { index in
                    PlayerRecordCard(name: names[index], color: Theme.playerColor(index), record: records[index])
                }

                winsCard("Caro wins", caroRecords, unit: "rounds")
                winsCard("Onet wins", onetRecords, unit: "games")

                Button("Reset scoreboard", role: .destructive) { confirmReset = true }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .padding(.top, Theme.Spacing.s)
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Scoreboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .alert("Reset all stats for \(names.joined(separator: " & "))?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                FindNumbersGame.records.reset(names)
                CaroGame.records.reset(names)
                OnetGame.records.reset(names)
                load()
            }
        }
    }

    /// Wins for each of you in one game, plus how many were played and drawn.
    private func winsCard(_ title: String, _ records: [PlayerRecord], unit: String) -> some View {
        let played = records.first?.duels ?? 0
        let draws = max(0, played - records.map(\.wins).reduce(0, +))
        return VStack(spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.plum)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                winsColumn(0, records)
                Text("–")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                winsColumn(1, records)
            }
            Text("\(played) \(unit) · \(draws) draws")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func winsColumn(_ index: Int, _ records: [PlayerRecord]) -> some View {
        VStack(spacing: 0) {
            Text("\(records.indices.contains(index) ? records[index].wins : 0)")
                .font(.system(size: 56, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.playerColor(index))
            Text(names[index])
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() {
        records = names.map(FindNumbersGame.records.record(for:))
        caroRecords = names.map(CaroGame.records.record(for:))
        onetRecords = names.map(OnetGame.records.record(for:))
    }
}

private struct PlayerRecordCard: View {
    let name: String
    let color: Color
    let record: PlayerRecord

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Circle().fill(color).frame(width: 14, height: 14)
                Text(name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(record.games) games")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
                metric("Wins", "\(record.wins)/\(record.duels)")
                metric("Win rate", record.winRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–")
                metric("Found", "\(record.found)")
                metric("Avg / find", record.averageFind.map { String(format: "%.2fs", $0) } ?? "–")
                metric("Fastest", record.fastestFind.map { String(format: "%.2fs", $0) } ?? "–")
                metric("Accuracy", record.accuracy.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–")
            }
        }
        .card()
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4).padding(.vertical, Theme.Spacing.l)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }
}
