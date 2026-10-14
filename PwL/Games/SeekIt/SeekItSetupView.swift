import SwiftUI

struct SeekItSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(AccountStore.self) private var account
    @Environment(NearbyService.self) private var nearby


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
                        PartnerConnectionCard(gameID: SeekItGame.gameID)
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
        .navigationTitle("Seek It")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.25), value: isWaitingGuest)
        .onAppear { nearby.onGameMessage = handleMessage }
    }

    @ViewBuilder
    private var settings: some View {
        section("Your journey") {
            Text("Six very messy rooms. Each hides 10 shapes among 50 things — find them all to open the next room.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
            VStack(spacing: 0) {
                ForEach(SeekItLevel.all, id: \.number) { level in
                    levelRow(level)
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
        let match = SeekItMatch(
            seed: .random(in: .min ... .max),
            playerNames: [localName, partner],
            localPlayer: 0
        )
        nearby.send(SeekItMessage.start(match))
        appState.path.append(.seekItMatch(match))
    }

    /// Guest side: the host started a match.
    private func handleMessage(_ data: Data) {
        guard case .start(var match) = try? JSONDecoder().decode(SeekItMessage.self, from: data) else { return }
        match.localPlayer = 1
        appState.path.append(.seekItMatch(match))
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.xs) {
            RoundedRectangle(cornerRadius: Theme.Radius.medium + 4, style: .continuous)
                .fill(LinearGradient(colors: [Theme.Scene.wood, Theme.peach], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 88, height: 88)
                .overlay { SeekItArtwork() }
                .shadow(color: Theme.Scene.wood.opacity(0.3), radius: 10, y: 5)
            Text("Race your love through six rooms — spot the hidden shapes first!")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, Theme.Spacing.s)
    }

    /// One stop on the level map: number badge on a dotted path, room preview, name.
    private func levelRow(_ level: SeekItLevel) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            ZStack {
                if level.number > 1 {
                    pathDots.offset(y: -30)
                }
                Text("\(level.number)")
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.brand, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .frame(width: 40)

            GeometryReader { geo in
                SeekItBackground(scene: level.scene)
                    .equatable()
                    .scaleEffect(geo.size.width / SeekItCanvas.width, anchor: .topLeading)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .frame(width: 110, height: 110 * SeekItCanvas.height / SeekItCanvas.width)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).stroke(.white, lineWidth: 2))
            .shadow(color: Theme.plum.opacity(0.15), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(level.scene.scene.title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("Find \(level.targetCount) of \(level.objectCount)")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Level \(level.number), \(level.scene.scene.title), find \(level.targetCount)")
    }

    /// Dotted trail connecting one level badge to the one above.
    private var pathDots: some View {
        VStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { _ in
                Circle().fill(Theme.rose.opacity(0.45)).frame(width: 5, height: 5)
            }
        }
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
