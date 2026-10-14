import SwiftUI

/// Each partner plays on their own device with an identical board (same seed) and races
/// for pairs. The host referees claims; pause / restart / leave are mirrored.
/// Played in landscape (wide board, HUD in the control bar); other screens stay portrait.
struct OnetGameView: View {
    @Environment(AppState.self) private var appState
    @Environment(AudioManager.self) private var audio
    @Environment(NearbyService.self) private var nearby
    @Environment(AccountStore.self) private var account
    @Environment(\.scenePhase) private var scenePhase

    @State private var game: OnetGame
    private let match: OnetMatch
    /// First tile of the local pick, or the pair waiting for the host's answer.
    @State private var selected: [Int] = []
    @State private var awaitingHost = false
    @State private var showMenu = false
    @State private var showHelp = false
    /// Whether closing the menu/help should resume (it was playing when opened).
    @State private var resumeOnClose = false
    @State private var partnerLeft = false
    @State private var showShuffled = false
    /// Level whose intro card is showing.
    @State private var levelIntro: OnetLevel?

    init(match: OnetMatch) {
        self.match = match
        _game = State(initialValue: OnetGame(config: match.config, playerNames: match.playerNames, seed: match.seed))
    }

    private var localPlayer: Int { match.localPlayer }
    private var partnerPlayer: Int { 1 - localPlayer }
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
                hud
            }
            board
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.s)
        .background(Theme.background.ignoresSafeArea())
        .overlay { overlay }
        .animation(.easeInOut(duration: 0.25), value: game.status)
        .animation(.easeInOut(duration: 0.25), value: showMenu)
        .animation(.easeInOut(duration: 0.25), value: isConnectionLost)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showHelp, onDismiss: closeModal) { OnetHelpView() }
        .sensoryFeedback(.selection, trigger: selected)
        .sensoryFeedback(.impact(weight: .light), trigger: game.players[localPlayer].pairs)
        .sensoryFeedback(.impact(weight: .heavy), trigger: game.players[partnerPlayer].pairs)
        .sensoryFeedback(.error, trigger: game.players[localPlayer].mistakes)
        .sensoryFeedback(.success, trigger: game.status == .finished)
        .onAppear {
            OrientationLock.set(.landscape)
            audio.setMusicActive(game.status == .playing)
            nearby.onGameMessage = handleMessage
        }
        .onDisappear {
            OrientationLock.set(.portrait)
            audio.setMusicActive(false)
        }
        .onChange(of: game.status) { _, status in
            audio.setMusicActive(status == .playing)
            // The host records the couple's stats once per finished game.
            if status == .finished, match.isHost, let result = game.result {
                Task { await account.recordGame(seconds: result.time) }
            }
        }
        .onChange(of: game.revision) {
            // The other player may have taken (or slid away) a tile we had picked.
            guard !awaitingHost else { return }
            if game.level.shifts || selected.contains(where: { game.tiles[$0] == nil }) { selected = [] }
        }
        .onChange(of: game.level) { _, level in
            resetPick()
            levelIntro = level
        }
        .task(id: levelIntro) {
            guard levelIntro != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            levelIntro = nil
        }
        .onChange(of: game.shuffleCount) { _, count in
            guard count > 0 else { return }
            selected = []
            showShuffled = true
        }
        .task(id: showShuffled) {
            guard showShuffled else { return }
            try? await Task.sleep(for: .seconds(1.6))
            showShuffled = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { pause() }
        }
    }

    // MARK: Board

    private var board: some View {
        OnetBoardView(game: game, player: localPlayer, selected: selected, onTap: handleTap)
            .overlay {
                if game.wrongPair[localPlayer] != nil {
                    lockoutOverlay
                }
            }
            .overlay(alignment: .top) {
                if showShuffled {
                    Label("No moves left — shuffled!", systemImage: "shuffle")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, Theme.Spacing.s)
                        .background(Theme.plum, in: Capsule())
                        .padding(.top, Theme.Spacing.s)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay {
                if let levelIntro {
                    levelCard(levelIntro)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: showShuffled)
            .animation(.spring(duration: 0.35), value: levelIntro)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .blur(radius: game.status == .paused ? 18 : 0)
            .allowsHitTesting(game.status == .playing && !isConnectionLost && levelIntro == nil)
            .animation(.easeInOut(duration: 0.2), value: game.wrongPair[localPlayer] != nil)
    }

    private func levelCard(_ level: OnetLevel) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("Level \(level.rawValue)")
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(Theme.ink)
            Label(level.title, systemImage: level.symbol)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.plum)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.l)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .shadow(color: Theme.plum.opacity(0.25), radius: 20, y: 8)
        .allowsHitTesting(false)
    }

    private var lockoutOverlay: some View {
        ZStack {
            Theme.danger.opacity(0.1)
            Label("Not a pair! Wait…", systemImage: "hand.raised.fill")
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

    /// One row for landscape: level, clock + pairs left, then both scores (you first).
    private var hud: some View {
        HStack(spacing: Theme.Spacing.m) {
            Label("\(game.level.rawValue)/\(game.levelCount)", systemImage: game.level.symbol)
                .font(.system(.subheadline, design: .rounded, weight: .black).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.brand, in: Capsule())
                .accessibilityLabel("Level \(game.level.rawValue) of \(game.levelCount), \(game.level.title)")
            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    Label(TimeFormat.clock(game.elapsed(at: context.date)), systemImage: "timer")
                        .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                }
                Text("\(game.pairsLeft) pairs left")
                    .font(.system(.caption2, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.inkSoft)
                    .contentTransition(.numericText(countsDown: true))
            }
            .labelStyle(OnetCompactLabelStyle())
            scoreChip(localPlayer, isYou: true)
            scoreChip(partnerPlayer, isYou: false)
        }
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
            Text("\(stats.pairs)")
                .font(.system(.subheadline, design: .rounded, weight: .black).monospacedDigit())
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: stats.pairs)
        }
        .font(.system(.caption, design: .rounded, weight: .bold))
        .foregroundStyle(Theme.ink)
        .padding(.leading, 3)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(.white.opacity(isYou ? 1 : 0.75), in: Capsule())
        .overlay(Capsule().stroke(Theme.playerColor(player).opacity(0.35), lineWidth: 1))
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
                Text("Take a breath — the tiles will wait.")
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
    private func resultSummary(_ result: OnetGame.Result) -> some View {
        Text(result.winnerIndex == nil ? "🤝" : result.winnerIndex == localPlayer ? "👑" : "😭")
            .font(.system(size: 52))
        Group {
            if let winner = result.winnerIndex {
                Text(winner == localPlayer ? "You win!" : "You lost")
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
            resultRow("Pairs", result, emphasized: true) { "\($0.pairs)" }
            resultRow("Mistakes", result) { "\($0.mistakes)" }
        }
        Text("Most pairs wins · ties go to fewer mistakes · \(TimeFormat.clock(result.time))")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
    }

    private func resultRow(
        _ title: String,
        _ result: OnetGame.Result,
        emphasized: Bool = false,
        value: @escaping (OnetGame.PlayerStats) -> String
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

    private func handleTap(_ index: Int) {
        guard game.status == .playing, !awaitingHost, !game.isLocked(localPlayer), game.tiles[index] != nil else { return }
        guard let first = selected.first else {
            selected = [index]
            return
        }
        if first == index {
            selected = []
            return
        }
        switch game.check(first, index, by: localPlayer) {
        case .match:
            if match.isHost {
                selected = []
                if let event = game.claim(first, index, by: localPlayer) {
                    nearby.send(OnetMessage.matched(event))
                }
            } else {
                // The host decides who was first; keep the pair lit until it answers.
                selected = [first, index]
                awaitingHost = true
                nearby.send(OnetMessage.claim(first: first, second: index, revision: game.revision))
            }
        case .noPath:
            // Same face but blocked: just switch the pick to the new tile.
            selected = [index]
        case .wrong:
            selected = []
            nearby.send(OnetMessage.mistake(player: localPlayer))
        case .ignored:
            selected = []
        }
    }

    private func handleMessage(_ data: Data) {
        guard let message = try? JSONDecoder().decode(OnetMessage.self, from: data) else { return }
        switch message {
        case .claim(let first, let second, let revision) where match.isHost:
            if let event = game.claim(first, second, by: partnerPlayer, revision: revision) {
                nearby.send(OnetMessage.matched(event))
            } else {
                nearby.send(OnetMessage.rejected(first: first, second: second))
            }
        case .matched(let event):
            game.applyMatch(event)
            // Ours went through, or the board moved on under it (the host will reject it).
            if awaitingHost, Set(selected) == [event.first, event.second] || game.level.shifts || selected.contains(where: { game.tiles[$0] == nil }) {
                awaitingHost = false
                selected = []
            }
        case .rejected:
            awaitingHost = false
            selected = []
        case .mistake(let player):
            game.applyMistake(by: player)
        case .pause:
            game.pause()
        case .resume:
            if !showMenu && !showHelp { game.resume() }
        case .restart(let seed):
            resetPick()
            game.restart(seed: seed)
        case .leave:
            partnerLeft = true
        case .start, .claim:
            break
        }
    }

    private func resetPick() {
        selected = []
        awaitingHost = false
    }

    private func pause() {
        guard game.status == .playing else { return }
        game.pause()
        nearby.send(OnetMessage.pause)
    }

    private func resume() {
        guard game.status == .paused else { return }
        game.resume()
        nearby.send(OnetMessage.resume)
    }

    private func restart() {
        let seed = UInt64.random(in: .min ... .max)
        resetPick()
        game.restart(seed: seed)
        nearby.send(OnetMessage.restart(seed: seed))
    }

    private enum Destination { case setup, games }

    private func leave(to destination: Destination) {
        nearby.send(OnetMessage.leave)
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

private struct OnetCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.caption.weight(.bold)).foregroundStyle(Theme.rose)
            configuration.title
        }
    }
}

struct OnetHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let rules: [(String, String)] = [
        ("flag.fill", "Tap two tiles with the same flag to link them."),
        ("arrow.turn.up.right", "The link line can turn at most twice and can't pass through other tiles — but it can run around the outside of the board."),
        ("bolt.fill", "You both play the same board at the same time. Whoever links a pair first scores it, and it disappears for both of you."),
        ("hand.raised.fill", "Picking two different flags is a mistake and freezes you for a moment."),
        ("shuffle", "No pairs left to link? The board shuffles itself."),
        ("stairs", "Play 1, 3 or all 9 levels. Clear the board to reach the next one; your points add up."),
        ("arrow.down", "From level 2 the tiles move after every match: down, up, left, right, then squeezing to the middle or spreading to the edges."),
        ("infinity", "No time limit — play at your own pace."),
        ("iphone.gen3.radiowaves.left.and.right", "Each of you plays on your own phone, nearby. One creates a room, the other joins."),
        ("trophy.fill", "Most pairs wins; ties go to fewer mistakes."),
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
