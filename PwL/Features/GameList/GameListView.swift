import SwiftUI

/// Catalog entry for the game list. Add new games here.
struct GameInfo: Identifiable {
    let id: String
    let title: String
    /// Small badge on the icon (e.g. "Coming soon"); `nil` shows none.
    let badge: String?
    let artwork: GameArtwork
    let colors: [Color]
    /// `nil` = coming soon.
    let route: Route?

    static let all: [GameInfo] = [
        GameInfo(
            id: "find-numbers",
            title: "Find Numbers",
            badge: nil,
            artwork: .findNumbers,
            colors: [Theme.rose, Theme.peach],
            route: .findNumbersSetup
        ),
        GameInfo(
            id: "coming-soon",
            title: "More games",
            badge: "Coming soon",
            artwork: .symbol("sparkles"),
            colors: [Theme.lilac, Theme.plum],
            route: nil
        ),
    ]
}

/// What a game tile draws inside its gradient square.
enum GameArtwork {
    case symbol(String)
    /// Scattered numbers under a magnifying glass.
    case findNumbers
}

struct GameListView: View {
    @Environment(AccountStore.self) private var account
    @Environment(AppState.self) private var appState

    @State private var query = ""

    private let columns = [GridItem(.flexible(), spacing: Theme.Spacing.m), GridItem(.flexible(), spacing: Theme.Spacing.m)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(account.isPaired ? "Hi \(account.nickname) & \(account.loveNickname)" : "Hi \(account.nickname)")
                        .font(.system(.title, design: .rounded, weight: .black))
                        .foregroundStyle(Theme.ink)
                    Text("Pick a game to play together")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                }

                if !account.isPaired {
                    Button {
                        appState.selectedTab = .settings
                    } label: {
                        Label(pairingPrompt, systemImage: account.incomingRequests.isEmpty ? "heart.circle.fill" : "envelope.open.fill")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.rose)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.m)
                            .background(Theme.rose.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                searchField

                if filteredGames.isEmpty {
                    VStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(.title, design: .rounded, weight: .semibold))
                        Text("No games match \u{201C}\(query)\u{201D}")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xl)
                }

                LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
                    ForEach(filteredGames) { game in
                        if let route = game.route {
                            NavigationLink(value: route) { GameTile(game: game) }
                                .buttonStyle(.plain)
                        } else {
                            GameTile(game: game).opacity(0.55)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var pairingPrompt: String {
        if let request = account.incomingRequests.first {
            return "\(request.fromNickname) wants to be your love. Tap to answer"
        }
        if let request = account.outgoingRequest {
            return "Waiting for \(request.toNickname) to accept your request"
        }
        return "Match with your love in Settings to start playing"
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkSoft)
            TextField("Search games", text: $query)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.ink)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, query.isEmpty ? 14 : 0)
        .frame(minHeight: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .shadow(color: Theme.plum.opacity(0.08), radius: 8, y: 4)
    }

    private var filteredGames: [GameInfo] {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return GameInfo.all }
        return GameInfo.all.filter {
            $0.route != nil && ($0.title.localizedCaseInsensitiveContains(term))
        }
    }
}

/// Square-icon tile. Every tile has the same width and height so the grid lines up.
private struct GameTile: View {
    let game: GameInfo

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .fill(LinearGradient(colors: game.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .aspectRatio(1, contentMode: .fit)
                .overlay { artwork }
                .overlay(alignment: .bottom) {
                    if let badge = game.badge {
                        Text(badge)
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.plum)
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.9), in: Capsule())
                            .padding(.bottom, Theme.Spacing.s)
                    }
                }
                .padding(.bottom, Theme.Spacing.xs)
            Text(game.title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.s + 4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large + 6, style: .continuous))
        .shadow(color: Theme.plum.opacity(0.1), radius: 12, y: 6)
    }

    @ViewBuilder
    private var artwork: some View {
        switch game.artwork {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        case .findNumbers:
            FindNumbersArtwork()
        }
    }
}
