import SwiftUI

/// Each partner plays on their own device with an identical board (same seed).
/// The host referees claims; pause / restart / leave are mirrored on both devices.
struct FindNumbersGameView: View {
    @Environment(AppState.self) private var appState
    @Environment(AudioManager.self) private var audio
    @Environment(NearbyService.self) private var nearby
    @Environment(AccountStore.self) private var account
    @Environment(\.scenePhase) private var scenePhase

    @State private var game: FindNumbersGame
    private let match: FindNumbersMatch
    @State private var showMenu = false
    @State private var showHelp = false
    /// Whether closing the menu/help should resume (it was playing when opened).
    @State private var resumeOnClose = false
    @State private var partnerLeft = false

    init(match: FindNumbersMatch) {
        self.match = match
        _game = State(initialValue: FindNumbersGame(
            config: match.config,
            playerNames: match.playerNames,
            paletteCount: Theme.tilePalette.count,
            seed: match.seed
        ))
    }

    private var localPlayer: Int { match.localPlayer }
    private var partnerPlayer: Int { 1 - localPlayer }
    private var isConnectionLost: Bool { partnerLeft || nearby.status == .lost }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            GameControlBar(
                isMusicOn: audio.isMusicOn,
                isPaused: game.status == .paused,
                onMenu: openMenu,
                onHelp: openHelp,
                onToggleMusic: audio.toggleMusic,
                onPause: togglePause
            ) {
                stats
            }
            banner
            board
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        .background(Theme.background.ignoresSafeArea())
        .overlay { overlay }
        .animation(.easeInOut(duration: 0.25), value: game.status)
        .animation(.easeInOut(duration: 0.25), value: showMenu)
        .animation(.easeInOut(duration: 0.25), value: isConnectionLost)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showHelp, onDismiss: closeModal) { FindNumbersHelpView() }
        .sensoryFeedback(.impact(weight: .light), trigger: game.players[localPlayer].found)
        .sensoryFeedback(.impact(weight: .heavy), trigger: game.players[partnerPlayer].found)
        .sensoryFeedback(.error, trigger: game.players[localPlayer].mistakes)
        .sensoryFeedback(.success, trigger: game.status == .finished)
        .onAppear {
            audio.setMusicActive(game.status == .playing)
            nearby.onGameMessage = handleMessage
        }
        .onDisappear { audio.setMusicActive(false) }
        .onChange(of: game.status) { _, status in
            audio.setMusicActive(status == .playing)
            // The host records the couple's stats once per finished game.
            if status == .finished, match.isHost, let result = game.result {
                Task { await account.recordGame(seconds: result.time) }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { pause() }
        }
    }

    // MARK: Board

    private var board: some View {
        NumberBoardView(game: game, player: localPlayer, onTap: handleTap)
            .background(Theme.Paper.sheet, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay {
                if game.blockedUntil[localPlayer] != nil {
                    blockOverlay
                } else if game.wrongValues[localPlayer] != nil {
                    lockoutOverlay
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .shadow(color: Theme.plum.opacity(0.12), radius: 12, y: 6)
            .blur(radius: game.status == .paused ? 18 : 0)
            .allowsHitTesting(game.status == .playing && !isConnectionLost)
            .animation(.easeInOut(duration: 0.2), value: game.wrongValues[localPlayer] != nil)
    }

    /// Shown after too many misses in a row; counts down on the game clock.
    private var blockOverlay: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let remaining = game.blockRemaining(for: localPlayer, at: context.date)
            ZStack {
                Theme.danger.opacity(0.18)
                if remaining > 0 {
                    VStack(spacing: Theme.Spacing.xs) {
                        Label("Too many misses!", systemImage: "hand.raised.fill")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        Text("Blocked for \(Int(remaining.rounded(.up)))s")
                            .font(.system(.title2, design: .rounded, weight: .black).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.m)
                    .background(Theme.danger, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                }
            }
            .opacity(remaining > 0 ? 1 : 0)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var lockoutOverlay: some View {
        ZStack {
            Theme.danger.opacity(0.12)
            Label("Oops! Wait…", systemImage: "hand.raised.fill")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .background(Theme.danger, in: Capsule())
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: HUD

    private var stats: some View {
        VStack(spacing: 2) {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                Label(TimeFormat.clock(game.elapsed(at: context.date)), systemImage: "timer")
                    .font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
            }
            Text("\(game.foundCount) / \(game.config.count)")
                .font(.system(.caption, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.inkSoft)
        }
        .labelStyle(CompactLabelStyle())
    }

    private var targetText: some View {
        Text(game.target.map(String.init) ?? "🎉")
            .font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .animation(.spring(duration: 0.3), value: game.target)
    }

    /// Target on the left, live score of both players on the right (you first).
    private var banner: some View {
        let color = Theme.playerColor(localPlayer)
        return HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Find")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                targetText
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                scoreChip(localPlayer, isYou: true)
                scoreChip(partnerPlayer, isYou: false)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(
            LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        )
    }

    private func scoreChip(_ player: Int, isYou: Bool) -> some View {
        let stats = game.players[player]
        return HStack(spacing: 6) {
            AvatarView(
                data: isYou ? account.account?.avatar : account.love?.avatar,
                name: stats.name,
                size: 26,
                color: Theme.playerColor(player)
            )
            .overlay(Circle().stroke(Theme.playerColor(player), lineWidth: 2))
            Text(isYou ? "You" : stats.name)
                .lineLimit(1)
                .frame(maxWidth: 80, alignment: .leading)
            // Always laid out (hidden when not leading) so both chips' scores line up.
            Image(systemName: "crown.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.orange)
                .opacity(game.leader == player ? 1 : 0)
                .accessibilityHidden(game.leader != player)
                .accessibilityLabel("Leading")
            Text("\(stats.found)")
                .font(.system(.subheadline, design: .rounded, weight: .black).monospacedDigit())
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: stats.found)
        }
        .font(.system(.caption, design: .rounded, weight: .bold))
        .foregroundStyle(Theme.ink)
        .padding(.leading, 3)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(.white.opacity(isYou ? 1 : 0.75), in: Capsule())
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlay: some View {
        if isConnectionLost {
            ModalCard {
                Image(systemName: partnerLeft ? "door.left.hand.open" : "wifi.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.brand)
                Text(partnerLeft ? "\(game.players[partnerPlayer].name) left the game" : "Connection lost")
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Button("Back to lobby") { appState.path.removeLast() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .transition(.opacity)
        } else if showMenu {
            ModalCard {
                Text("Menu")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .foregroundStyle(Theme.ink)
                Button("Resume") { showMenu = false; closeModal() }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Restart") { showMenu = false; resumeOnClose = false; restart() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Back to lobby") { showMenu = false; leave(to: .setup) }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Quit to games") { showMenu = false; leave(to: .games) }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .transition(.opacity)
        } else if game.status == .paused && !showHelp {
            ModalCard {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.brand)
                Text("Paused")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .foregroundStyle(Theme.ink)
                Text("Take a breath — the numbers will wait.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                Button("Resume", action: resume)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .transition(.opacity)
        } else if game.status == .finished, let result = game.result {
            ModalCard {
                resultSummary(result)
                Button("Play again", action: restart)
                    .buttonStyle(PrimaryButtonStyle())
                HStack(spacing: Theme.Spacing.s) {
                    Button("Lobby") { leave(to: .setup) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Games") { leave(to: .games) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    @ViewBuilder
    private func resultSummary(_ result: FindNumbersGame.Result) -> some View {
        Text(result.winnerIndex == nil ? "🤝" : result.winnerIndex == localPlayer ? "👑" : "💪")
            .font(.system(size: 52))
        Group {
            if let winner = result.winnerIndex {
                Text(winner == localPlayer ? "You win!" : "\(result.players[winner].name) wins!")
                    .foregroundStyle(Theme.playerColor(winner))
            } else {
                Text("It's a tie!")
                    .foregroundStyle(Theme.ink)
            }
        }
        .font(.system(.title, design: .rounded, weight: .black))
        .lineLimit(1)
        .minimumScaleFactor(0.6)

        Grid(horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.s) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(result.players.indices, id: \.self) { index in
                    Text(result.players[index].name)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.playerColor(index))
                        .lineLimit(1)
                }
            }
            Divider().gridCellColumns(result.players.count + 1)
            duelRow("Points", result, emphasized: true) { "\($0.found)" }
            duelRow("Mistakes", result) { "\($0.mistakes)" }
            duelRow("Avg reaction", result) { $0.averageFind.map { String(format: "%.2fs", $0) } ?? "–" }
            duelRow("Fastest", result) { $0.fastest.map { String(format: "%.2fs", $0) } ?? "–" }
        }
        Text("Most numbers wins · ties go to fewer mistakes, then faster reactions")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
    }

    private func duelRow(
        _ title: String,
        _ result: FindNumbersGame.Result,
        emphasized: Bool = false,
        value: @escaping (FindNumbersGame.PlayerStats) -> String
    ) -> some View {
        GridRow {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .gridColumnAlignment(.leading)
            ForEach(result.players.indices, id: \.self) { index in
                Text(value(result.players[index]))
                    .font(.system(emphasized ? .title3 : .subheadline, design: .rounded, weight: emphasized ? .black : .semibold).monospacedDigit())
                    .foregroundStyle(emphasized && index == result.winnerIndex ? Theme.playerColor(index) : Theme.ink)
            }
        }
    }

    // MARK: Taps & network

    private func handleTap(_ value: Int) {
        switch game.check(value, by: localPlayer) {
        case .wrong:
            nearby.send(FindNumbersMessage.mistake(player: localPlayer))
        case .correct where match.isHost:
            if let event = game.claim(value, by: localPlayer) {
                nearby.send(FindNumbersMessage.found(event))
            }
        case .correct:
            // The host decides who was first.
            nearby.send(FindNumbersMessage.claim(value: value))
        default:
            break
        }
    }

    private func handleMessage(_ data: Data) {
        guard let message = try? JSONDecoder().decode(FindNumbersMessage.self, from: data) else { return }
        switch message {
        case .claim(let value) where match.isHost:
            if let event = game.claim(value, by: partnerPlayer) {
                nearby.send(FindNumbersMessage.found(event))
            }
        case .found(let event):
            game.applyFound(event)
        case .mistake(let player):
            game.applyMistake(by: player)
        case .pause:
            game.pause()
        case .resume:
            if !showMenu && !showHelp { game.resume() }
        case .restart(let seed):
            game.restart(seed: seed)
        case .leave:
            partnerLeft = true
        case .start, .claim:
            break
        }
    }

    private func pause() {
        guard game.status == .playing else { return }
        game.pause()
        nearby.send(FindNumbersMessage.pause)
    }

    private func resume() {
        guard game.status == .paused else { return }
        game.resume()
        nearby.send(FindNumbersMessage.resume)
    }

    private func restart() {
        let seed = UInt64.random(in: .min ... .max)
        game.restart(seed: seed)
        nearby.send(FindNumbersMessage.restart(seed: seed))
    }

    private enum Destination { case setup, games }

    private func leave(to destination: Destination) {
        nearby.send(FindNumbersMessage.leave)
        switch destination {
        case .setup: appState.path.removeLast()
        case .games: appState.path.removeAll()
        }
    }

    private func togglePause() {
        switch game.status {
        case .playing: pause()
        case .paused: resume()
        case .finished: break
        }
    }

    private func openMenu() {
        resumeOnClose = game.status == .playing
        pause()
        showMenu = true
    }

    private func openHelp() {
        resumeOnClose = game.status == .playing
        pause()
        showHelp = true
    }

    private func closeModal() {
        if resumeOnClose { resume() }
        resumeOnClose = false
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.caption.weight(.bold)).foregroundStyle(Theme.rose)
            configuration.title
        }
    }
}

struct FindNumbersHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let rules: [(String, String)] = [
        ("number.circle.fill", "Numbers are scattered across the sheet in different sizes and angles."),
        ("hand.tap.fill", "Tap them in order: 1, 2, 3…, counting down for N → 1, or whatever number the game picks in Random."),
        ("text.badge.checkmark", "The banner always shows the number to find next. Found numbers get circled."),
        ("underline", "Underlined numbers (like 6 and 9) show which way is up."),
        ("arrow.up.left.and.arrow.down.right", "On big boards, pinch to zoom and drag to scroll."),
        ("iphone.gen3.radiowaves.left.and.right", "Each of you plays on your own phone, nearby. One creates a room, the other joins."),
        ("bolt.fill", "You both see the same board and hunt for the same number — whoever taps it first wins the point and circles it in their color."),
        ("hand.raised.fill", "A wrong tap freezes you for a moment, so don't just mash!"),
        ("hand.raised.fill", "Miss \(FindNumbersGame.missesBeforeBlock) times in a row and you're blocked for \(Int(FindNumbersGame.missBlock)) seconds."),
        ("trophy.fill", "Most points wins. Check the Scoreboard for lifetime stats."),
    ]

    var body: some View {
        NavigationStack {
            List(rules, id: \.1) { icon, text in
                Label {
                    Text(text).font(.system(.body, design: .rounded))
                } icon: {
                    Image(systemName: icon).foregroundStyle(Theme.rose)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("How to play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Got it") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
