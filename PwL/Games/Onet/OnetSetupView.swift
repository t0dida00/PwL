import SwiftUI

struct OnetSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(AccountStore.self) private var account
    @Environment(NearbyService.self) private var nearby

    @AppStorage("onet.levels") private var levels: OnetConfig.Levels = .three

    private var localName: String { account.nickname }
    /// A connected guest waits while the host picks settings.
    private var isWaitingGuest: Bool { nearby.isConnected && !nearby.isHost }
    private var canStart: Bool { nearby.isConnected && nearby.isHost }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                header

                section("Your love") {
                    if account.isPaired {
                        PartnerConnectionCard(gameID: OnetGame.gameID)
                    } else {
                        notMatched
                    }
                }

                if isWaitingGuest {
                    waitingForHost
                } else {
                    settings
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Onet")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.25), value: isWaitingGuest)
        .onAppear { nearby.onGameMessage = handleMessage }
    }

    @ViewBuilder
    private var settings: some View {
        section("Levels") {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(OnetConfig.Levels.allCases, id: \.self) { option in
                    ChipButton(title: option.title, isSelected: levels == option) { levels = option }
                }
            }
            Text("\(OnetConfig.columns) × \(OnetConfig.rows) board · \(OnetConfig.kindCount) flags · \(OnetConfig.pairs) pairs per level")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.plum)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(OnetLevel.allCases.prefix(levels.count), id: \.self) { level in
                    Label("\(level.rawValue). \(level.title)", systemImage: level.symbol)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }

        Button("Start match", action: start)
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canStart)
            .padding(.top, Theme.Spacing.s)
        if !nearby.isConnected {
            Text("Connect with \(account.loveNickname) to start")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var notMatched: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Match with your love first — enter their PwL ID in Settings.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
            Button("Go to Settings") { appState.selectedTab = .settings }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var waitingForHost: some View {
        VStack(spacing: Theme.Spacing.s) {
            ProgressView()
            Text("Waiting for \(nearby.partnerName ?? account.loveNickname) to pick the settings and start…")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func start() {
        var partner = nearby.partnerName ?? account.loveNickname
        if partner.lowercased() == localName.lowercased() { partner += " 2" }
        let match = OnetMatch(
            config: OnetConfig(levels: levels),
            seed: .random(in: .min ... .max),
            playerNames: [localName, partner],
            localPlayer: 0
        )
        nearby.send(OnetMessage.start(match))
        appState.path.append(.onetMatch(match))
    }

    /// Guest side: the host started a match.
    private func handleMessage(_ data: Data) {
        guard case .start(var match) = try? JSONDecoder().decode(OnetMessage.self, from: data) else { return }
        match.localPlayer = 1
        appState.path.append(.onetMatch(match))
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.xs) {
            RoundedRectangle(cornerRadius: Theme.Radius.medium + 4, style: .continuous)
                .fill(LinearGradient(colors: [Theme.peach, Theme.lilac], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 88, height: 88)
                .overlay { OnetArtwork() }
                .shadow(color: Theme.lilac.opacity(0.3), radius: 10, y: 5)
            Text("Race your love to link matching tiles — the line can turn at most twice!")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, Theme.Spacing.s)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.plum)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
