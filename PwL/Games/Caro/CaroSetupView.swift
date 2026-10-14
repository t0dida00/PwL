import SwiftUI

struct CaroSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(AccountStore.self) private var account
    @Environment(NearbyService.self) private var nearby

    @AppStorage("caro.rule") private var rule: CaroConfig.Rule = .blockedEnds

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
                        PartnerConnectionCard(gameID: CaroGame.gameID)
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
        .navigationTitle("Caro")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.25), value: isWaitingGuest)
        .onAppear { nearby.onGameMessage = handleMessage }
    }

    @ViewBuilder
    private var settings: some View {
        section("Rule") {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(CaroConfig.Rule.allCases, id: \.self) { option in
                    ChipButton(title: option.title, isSelected: rule == option) { rule = option }
                }
            }
            Text(ruleDescription)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
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

    private var ruleDescription: String {
        switch rule {
        case .free: "Five or more in a row wins."
        case .blockedEnds: "Five in a row wins — unless both ends are blocked by your love's marks."
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
        let match = CaroMatch(
            config: CaroConfig(rule: rule),
            playerNames: [localName, partner],
            localPlayer: 0
        )
        nearby.send(CaroMessage.start(match))
        appState.path.append(.caroMatch(match))
    }

    /// Guest side: the host started a match.
    private func handleMessage(_ data: Data) {
        guard case .start(var match) = try? JSONDecoder().decode(CaroMessage.self, from: data) else { return }
        match.localPlayer = 1
        appState.path.append(.caroMatch(match))
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.xs) {
            RoundedRectangle(cornerRadius: Theme.Radius.medium + 4, style: .continuous)
                .fill(LinearGradient(colors: [Theme.plum, Theme.rose], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 88, height: 88)
                .overlay { CaroArtwork() }
                .shadow(color: Theme.plum.opacity(0.25), radius: 10, y: 5)
            Text("Take turns with X and O on a 100×100 sheet — first to get five in a row wins!")
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
