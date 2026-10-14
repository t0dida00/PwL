import SwiftUI

/// Each partner plays on their own device. Moves are mirrored; pause / restart / leave too.
struct CaroGameView: View {
    @Environment(AppState.self) private var appState
    @Environment(AudioManager.self) private var audio
    @Environment(NearbyService.self) private var nearby
    @Environment(AccountStore.self) private var account
    @Environment(\.scenePhase) private var scenePhase

    @State private var game: CaroGame
    private let match: CaroMatch
    @State private var showMenu = false
    @State private var showHelp = false
    /// Whether closing the menu/help should resume (it was playing when opened).
    @State private var resumeOnClose = false
    @State private var partnerLeft = false

    init(match: CaroMatch) {
        self.match = match
        _game = State(initialValue: CaroGame(config: match.config, playerNames: match.playerNames))
    }

    private var localPlayer: Int { match.localPlayer }
    private var partnerPlayer: Int { 1 - localPlayer }
    private var isMyTurn: Bool { game.turn == localPlayer }
    private var isConnectionLost: Bool { partnerLeft || !nearby.isConnected }

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
        .animation(.easeInOut(duration: 0.25), value: game.turn)
        .animation(.easeInOut(duration: 0.25), value: showMenu)
        .animation(.easeInOut(duration: 0.25), value: isConnectionLost)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showHelp, onDismiss: closeModal) { CaroHelpView() }
        .sensoryFeedback(.impact(weight: .light), trigger: game.moves.count)
        .sensoryFeedback(.success, trigger: game.status == .finished)
        .onAppear {
            audio.setMusicActive(game.status == .playing)
            nearby.onGameMessage = handleMessage
        }
        .onDisappear { audio.setMusicActive(false) }
        .onChange(of: game.status) { _, status in
            audio.setMusicActive(status == .playing)
            // The host records the couple's stats once per finished round.
            if status == .finished, match.isHost {
                Task { await account.recordGame(seconds: game.elapsed()) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { pause() }
        }
    }

    // MARK: Board

    private var board: some View {
        CaroBoardView(game: game, onTap: handleTap)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .shadow(color: Theme.plum.opacity(0.12), radius: 12, y: 6)
            .blur(radius: game.status == .paused ? 18 : 0)
            .allowsHitTesting(game.status == .playing && isMyTurn && !isConnectionLost)
    }

    // MARK: HUD

    private var stats: some View {
        VStack(spacing: 2) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Label(TimeFormat.clock(game.elapsed(at: context.date)).dropLast(2), systemImage: "timer")
                    .font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
            }
            Text("Move \(game.moves.count)")
                .font(.system(.caption, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.inkSoft)
        }
        .labelStyle(CaroCompactLabelStyle())
    }

    /// Whose turn on the left, both players with their mark and series wins on the right.
    private var banner: some View {
        let color = Theme.playerColor(game.turn)
        return HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text(game.status == .finished ? "Round over" : isMyTurn ? "Your turn" : "\(game.playerNames[game.turn])'s turn")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Text(game.mark(of: game.turn))
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                playerChip(localPlayer, isYou: true)
                playerChip(partnerPlayer, isYou: false)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(
            LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        )
    }

    private func playerChip(_ player: Int, isYou: Bool) -> some View {
        let isTurn = game.turn == player && game.status != .finished
        return HStack(spacing: 6) {
            AvatarView(
                data: isYou ? account.account?.avatar : account.love?.avatar,
                name: game.playerNames[player],
                size: 26,
                color: Theme.playerColor(player)
            )
            .overlay(Circle().stroke(Theme.playerColor(player), lineWidth: 2))
            Text(isYou ? "You" : game.playerNames[player])
                .lineLimit(1)
                .frame(maxWidth: 70, alignment: .leading)
            Text(game.mark(of: player))
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .foregroundStyle(Theme.playerColor(player))
            Text("\(game.score[player])")
                .font(.system(.subheadline, design: .rounded, weight: .black).monospacedDigit())
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: game.score[player])
        }
        .font(.system(.caption, design: .rounded, weight: .bold))
        .foregroundStyle(Theme.ink)
        .padding(.leading, 3)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(.white.opacity(isTurn ? 1 : 0.7), in: Capsule())
        .scaleEffect(isTurn ? 1.04 : 1)
        .accessibilityElement(children: .combine)
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlay: some View {
        if isConnectionLost {
            ModalCard {
                Image(systemName: partnerLeft ? "door.left.hand.open" : "wifi.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.brand)
                Text(partnerLeft ? "\(game.playerNames[partnerPlayer]) left the game" : "Connection lost")
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Button("Back to lobby") { appState.leaveScreen() }
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
                Button("Change settings") { showMenu = false; leave(to: .setup) }
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
                Text("Take a breath — the board will wait.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                Button("Resume", action: resume)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .transition(.opacity)
        } else if game.status == .finished {
            ModalCard {
                resultSummary
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
    private var resultSummary: some View {
        Text(game.winner == nil ? "🤝" : game.winner == localPlayer ? "👑" : "😭")
            .font(.system(size: 52))
        Group {
            if let winner = game.winner {
                Text(winner == localPlayer ? "You win!" : "You lost")
                    .foregroundStyle(Theme.playerColor(winner))
            } else {
                Text("Board full — draw!")
                    .foregroundStyle(Theme.ink)
            }
        }
        .font(.system(.title, design: .rounded, weight: .black))
        .lineLimit(1)
        .minimumScaleFactor(0.6)

        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            seriesColumn(localPlayer)
            Text("–")
                .font(.system(.title, design: .rounded, weight: .black))
                .foregroundStyle(Theme.inkSoft)
            seriesColumn(partnerPlayer)
        }
        Text("\(game.moves.count) moves · next round \(game.playerNames[1 - game.startingPlayer]) goes first")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
    }

    private func seriesColumn(_ player: Int) -> some View {
        VStack(spacing: 0) {
            Text("\(game.score[player])")
                .font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.playerColor(player))
            Text(player == localPlayer ? "You" : game.playerNames[player])
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Taps & network

    private func handleTap(_ index: Int) {
        guard game.status == .playing, isMyTurn else { return }
        if game.place(at: index, by: localPlayer) != .ignored {
            nearby.send(CaroMessage.move(index: index))
        }
    }

    private func handleMessage(_ data: Data) {
        guard let message = try? JSONDecoder().decode(CaroMessage.self, from: data) else { return }
        switch message {
        case .move(let index):
            game.place(at: index, by: partnerPlayer)
        case .pause:
            game.pause()
        case .resume:
            if !showMenu && !showHelp { game.resume() }
        case .restart(let round):
            game.restart(round: round)
        case .leave:
            partnerLeft = true
        case .start:
            break
        }
    }

    private func pause() {
        guard game.status == .playing else { return }
        game.pause()
        nearby.send(CaroMessage.pause)
    }

    private func resume() {
        guard game.status == .paused else { return }
        game.resume()
        nearby.send(CaroMessage.resume)
    }

    private func restart() {
        game.restart()
        nearby.send(CaroMessage.restart(round: game.round))
    }

    private enum Destination { case setup, games }

    private func leave(to destination: Destination) {
        nearby.send(CaroMessage.leave)
        switch destination {
        case .setup: appState.leaveScreen()
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

private struct CaroCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.caption.weight(.bold)).foregroundStyle(Theme.rose)
            configuration.title
        }
    }
}

struct CaroHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let rules: [(String, String)] = [
        ("square.grid.3x3", "Take turns placing your mark on the squared paper. Whoever starts plays X, the other plays O."),
        ("line.diagonal", "Get five in a row (across, down or diagonal) to win the round."),
        ("shield.lefthalf.filled", "Vietnamese rule: a five blocked by your love's marks at both ends doesn't count. Free rule: any five or more wins."),
        ("arrow.triangle.2.circlepath", "Each round, the other player moves first. The series score keeps counting until you leave."),
        ("arrow.up.and.down.and.arrow.left.and.right", "The sheet is 100×100: drag to move around and pinch to zoom. The view jumps to your love's move, and the target button brings you back to the last move."),
        ("iphone.gen3.radiowaves.left.and.right", "Each of you plays on your own phone, nearby. One creates a room, the other joins."),
        ("trophy.fill", "Check the Scoreboard for your lifetime wins."),
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
