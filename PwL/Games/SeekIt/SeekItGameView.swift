import SwiftUI

/// Each partner plays on their own device with the identical room (same seed) and races
/// to find the listed objects. The host referees claims; pause / restart / leave are
/// mirrored. Played in landscape; other screens stay portrait.
struct SeekItGameView: View {
    @Environment(AppState.self) private var appState
    @Environment(AudioManager.self) private var audio
    @Environment(NearbyService.self) private var nearby
    @Environment(AccountStore.self) private var account
    @Environment(\.scenePhase) private var scenePhase

    @State private var game: SeekItGame
    private let match: SeekItMatch
    @State private var showMenu = false
    @State private var showHelp = false
    /// Whether closing the menu/help should resume (it was playing when opened).
    @State private var resumeOnClose = false
    @State private var partnerLeft = false
    @State private var hinted: Int?
    @State private var missMark: CGPoint?
    /// Target the guest is waiting on the host for (no double claims).
    @State private var pendingClaim: Int?
    /// Level whose intro card is showing (also at the start).
    @State private var levelIntro: SeekItLevel? = SeekItLevel(1)

    init(match: SeekItMatch) {
        self.match = match
        _game = State(initialValue: SeekItGame(playerNames: match.playerNames, seed: match.seed))
    }

    private var localPlayer: Int { match.localPlayer }
    private var partnerPlayer: Int { 1 - localPlayer }
    private var isConnectionLost: Bool { partnerLeft || !nearby.isConnected }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
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
            room
            tray
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xs)
        .background(Theme.background.ignoresSafeArea())
        .overlay { overlay }
        .animation(.easeInOut(duration: 0.25), value: game.status)
        .animation(.easeInOut(duration: 0.25), value: showMenu)
        .animation(.easeInOut(duration: 0.25), value: isConnectionLost)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showHelp, onDismiss: closeModal) { SeekItHelpView() }
        .sensoryFeedback(.impact(weight: .light), trigger: game.players[localPlayer].found)
        .sensoryFeedback(.impact(weight: .heavy), trigger: game.players[partnerPlayer].found)
        .sensoryFeedback(.error, trigger: game.missCount[localPlayer])
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
        .onChange(of: game.level) { _, level in
            resetLocal()
            levelIntro = level
        }
        .task(id: levelIntro) {
            guard levelIntro != nil else { return }
            try? await Task.sleep(for: .seconds(2.2))
            levelIntro = nil
        }
        .onChange(of: game.foundBy) {
            if let hinted, game.foundBy[hinted] != nil { self.hinted = nil }
            if let pendingClaim, game.foundBy[pendingClaim] != nil { self.pendingClaim = nil }
        }
        .task(id: hinted) {
            guard hinted != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            hinted = nil
        }
        .task(id: missMark) {
            guard missMark != nil else { return }
            try? await Task.sleep(for: .seconds(0.6))
            missMark = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { pause() }
        }
    }

    // MARK: Room

    private var room: some View {
        SeekItSceneView(game: game, hinted: hinted, missMark: missMark, onTap: handleTap)
            .overlay {
                if game.blockedUntil[localPlayer] != nil {
                    blockOverlay
                }
            }
            .overlay {
                if let levelIntro {
                    levelCard(levelIntro)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.4), value: levelIntro)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .shadow(color: Theme.plum.opacity(0.15), radius: 10, y: 4)
            .blur(radius: game.status == .paused ? 18 : 0)
            .allowsHitTesting(game.status == .playing && !isConnectionLost && levelIntro == nil)
    }

    /// "Level 3 · Secret Garden ★★" card shown as each room opens.
    private func levelCard(_ level: SeekItLevel) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("Level \(level.number) of \(SeekItLevel.count)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.plum)
            Text(level.scene.scene.title)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(Theme.ink)
            Text("Find \(level.targetCount) shapes among \(level.objectCount) things")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.l)
        .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .shadow(color: Theme.plum.opacity(0.3), radius: 24, y: 10)
        .allowsHitTesting(false)
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
    }

    // MARK: HUD & tray

    private var hud: some View {
        HStack(spacing: Theme.Spacing.m) {
            Label("\(game.level.number)/\(SeekItLevel.count)", systemImage: "magnifyingglass")
                .font(.system(.subheadline, design: .rounded, weight: .black).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.brand, in: Capsule())
                .accessibilityLabel("Level \(game.level.number) of \(SeekItLevel.count), \(game.scene.title)")
            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    Label(TimeFormat.clock(game.elapsed(at: context.date)), systemImage: "timer")
                        .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                }
                Text("\(game.foundCount) / \(game.targetCount) found")
                    .font(.system(.caption2, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.inkSoft)
            }
            .labelStyle(SeekItCompactLabelStyle())
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
        .overlay(Capsule().stroke(Theme.playerColor(player).opacity(0.35), lineWidth: 1))
    }

    /// The shapes to find (still-to-find first, found ones slide to the end), a
    /// "left" counter, and the hint button.
    private var tray: some View {
        let order = game.layout.targets.enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (game.foundBy[lhs.element] != nil, game.foundBy[rhs.element] != nil)
                return a == b ? lhs.offset < rhs.offset : !a
            }
            .map(\.element)
        return HStack(spacing: Theme.Spacing.s) {
            VStack(spacing: 0) {
                Text("\(game.targetCount - game.foundCount)")
                    .font(.system(.title3, design: .rounded, weight: .black).monospacedDigit())
                    .foregroundStyle(Theme.rose)
                    .contentTransition(.numericText(countsDown: true))
                Text("left")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(width: 40)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(order, id: \.self) { id in
                        if let placement = game.layout.placement(id) {
                            clueCard(placement, finder: game.foundBy[id])
                        }
                    }
                }
                .padding(.horizontal, 2)
                .animation(.spring(duration: 0.4), value: game.foundBy)
            }
            Button(action: useHint) {
                HStack(spacing: 4) {
                    Text("💡").font(.system(size: 20))
                    Text("\(game.hintsLeft[localPlayer])")
                        .font(.system(.headline, design: .rounded, weight: .black).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.Scene.sun.opacity(game.hintsLeft[localPlayer] > 0 ? 0.6 : 0.2), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(game.hintsLeft[localPlayer] == 0 || game.status != .playing || hinted != nil)
            .accessibilityLabel("Hint, \(game.hintsLeft[localPlayer]) left")
        }
        .frame(height: 50)
    }

    /// A clue is the object's dark silhouette — its shape, no words. Once found it
    /// turns into the real, colored object with a check in the finder's color.
    private func clueCard(_ placement: SeekItPlacement, finder: Int?) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        return ZStack {
            if finder == nil {
                Text(placement.emoji)
                    .font(.system(size: 28))
                    .colorMultiply(Theme.ink)
                    .opacity(0.85)
            } else {
                Text(placement.emoji)
                    .font(.system(size: 28))
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(width: 46, height: 44)
        .background(finder == nil ? Theme.Scene.paper : Theme.Scene.paper.opacity(0.6), in: shape)
        .overlay(shape.stroke(finder.map { Theme.playerColor($0) } ?? Theme.plum.opacity(0.15), lineWidth: finder == nil ? 1 : 2.5))
        .overlay(alignment: .topTrailing) {
            if let finder {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white, Theme.playerColor(finder))
                    .offset(x: 5, y: -5)
            }
        }
        .animation(.spring(duration: 0.35), value: finder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(finder == nil ? "Find: \(placement.name)" : "\(placement.name), found")
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
                Text("Take a breath — everything stays hidden.")
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
    private func resultSummary(_ result: SeekItGame.Result) -> some View {
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
            resultRow("Found", result, emphasized: true) { "\($0.found)" }
            resultRow("Mistakes", result) { "\($0.mistakes)" }
            resultRow("Avg find", result) { $0.averageFind.map { String(format: "%.1fs", $0) } ?? "–" }
        }
        Text("All \(SeekItLevel.count) rooms · \(TimeFormat.clock(result.time))")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
    }

    private func resultRow(
        _ title: String,
        _ result: SeekItGame.Result,
        emphasized: Bool = false,
        value: @escaping (SeekItGame.PlayerStats) -> String
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

    private func handleTap(_ point: CGPoint) {
        guard game.status == .playing else { return }
        switch game.check(point, by: localPlayer) {
        case .hit(let id):
            if match.isHost {
                if let event = game.claim(id, by: localPlayer) {
                    nearby.send(SeekItMessage.found(event))
                }
            } else if pendingClaim != id {
                // The host decides who was first.
                pendingClaim = id
                nearby.send(SeekItMessage.claim(id: id, level: game.level.number))
            }
        case .miss:
            missMark = point
            nearby.send(SeekItMessage.mistake(player: localPlayer))
        case .ignored:
            break
        }
    }

    private func useHint() {
        guard hinted == nil, let id = game.useHint(by: localPlayer) else { return }
        hinted = id
    }

    private func handleMessage(_ data: Data) {
        guard let message = try? JSONDecoder().decode(SeekItMessage.self, from: data) else { return }
        switch message {
        case .claim(let id, let level) where match.isHost:
            if let event = game.claim(id, by: partnerPlayer, level: level) {
                nearby.send(SeekItMessage.found(event))
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
            resetLocal()
            game.restart(seed: seed)
            levelIntro = game.level
        case .leave:
            partnerLeft = true
        case .start, .claim:
            break
        }
    }

    private func resetLocal() {
        hinted = nil
        missMark = nil
        pendingClaim = nil
    }

    private func pause() {
        guard game.status == .playing else { return }
        game.pause()
        nearby.send(SeekItMessage.pause)
    }

    private func resume() {
        guard game.status == .paused else { return }
        game.resume()
        nearby.send(SeekItMessage.resume)
    }

    private func restart() {
        let seed = UInt64.random(in: .min ... .max)
        resetLocal()
        game.restart(seed: seed)
        levelIntro = game.level
        nearby.send(SeekItMessage.restart(seed: seed))
    }

    private enum Destination { case setup, games }

    private func leave(to destination: Destination) {
        nearby.send(SeekItMessage.leave)
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

private struct SeekItCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.caption.weight(.bold)).foregroundStyle(Theme.rose)
            configuration.title
        }
    }
}

struct SeekItHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let rules: [(String, String)] = [
        ("magnifyingglass", "The bottom bar shows the shapes of the objects to find — spot the real thing hidden in the room."),
        ("stairs", "Play through \(SeekItLevel.count) rooms. Clear a room and the next one opens; your finds add up."),
        ("hand.tap.fill", "Tap an object to grab it. Pinch to zoom in and drag to look around."),
        ("bolt.fill", "You both search the same room at the same time — whoever taps an object first scores it and circles it in their color."),
        ("hand.raised.fill", "Tapping the wrong thing freezes you for a moment. Miss \(SeekItGame.missesBeforeBlock) times in a row and you're blocked for \(Int(SeekItGame.missBlock)) seconds."),
        ("lightbulb.fill", "Stuck? Tap 💡 to make one object glow — just on your screen. Hints are limited."),
        ("eye.slash.fill", "Every room is a mess: 50 different things in all sizes, piled up, tilted, half-buried under papers and leaves, with look-alikes to trick you."),
        ("iphone.gen3.radiowaves.left.and.right", "Each of you plays on your own phone, nearby. One creates a room, the other joins."),
        ("trophy.fill", "Most objects found wins; ties go to fewer mistakes, then faster finds."),
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
