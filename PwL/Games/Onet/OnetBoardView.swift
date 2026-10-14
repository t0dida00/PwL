import SwiftUI

/// Tile faces: country flags (index = face kind). Picked to look clearly different
/// from each other (no near-twins like Indonesia/Monaco or Australia/New Zealand).
enum OnetTileFace {
    static let emoji = [
        "🇻🇳", "🇺🇸", "🇯🇵", "🇰🇷", "🇨🇳", "🇬🇧", "🇫🇷", "🇩🇪", "🇮🇹", "🇪🇸", "🇧🇷", "🇨🇦",
        "🇦🇺", "🇮🇳", "🇹🇭", "🇸🇪", "🇰🇪", "🇳🇴", "🇨🇭", "🇬🇷", "🇹🇷", "🇵🇹", "🇦🇷", "🇲🇽",
        "🇿🇦", "🇪🇬", "🇸🇦", "🇮🇱", "🇯🇲", "🇱🇰", "🇺🇦", "🇵🇭", "🇸🇬", "🇵🇱", "🇨🇴", "🇳🇵",
    ]

    static func emoji(for kind: Int) -> String { emoji[kind % emoji.count] }
}

/// The tile board with a one-cell margin all round, where link lines may run.
/// Pinch to zoom and drag to scroll when tiles would be too small.
struct OnetBoardView: View {
    let game: OnetGame
    /// This device's player (selection color).
    let player: Int
    /// The local pick waiting for its pair (or for the host's answer).
    let selected: [Int]
    let onTap: (Int) -> Void

    /// Tile height / width: a little wider than tall, to suit flags in landscape.
    private let aspect: CGFloat = 0.86
    private let minWidth: CGFloat = 30
    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1
    /// The link line currently flashing.
    @State private var flash: OnetGame.Match?

    var body: some View {
        GeometryReader { geo in
            let rows = game.rows, columns = game.columns
            // One extra tile of margin (half each side) for links around the outside.
            let fitWidth = min(geo.size.width / CGFloat(columns + 1), geo.size.height / (CGFloat(rows + 1) * aspect))
            let width = max(fitWidth, minWidth) * zoom
            let height = width * aspect
            let content = CGSize(width: width * CGFloat(columns + 1), height: height * CGFloat(rows + 1))

            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Keyed by tile identity, so tiles visibly slide on moving levels.
                    ForEach(placedTiles, id: \.id) { placed in
                        let index = placed.cell
                        if let kind = game.tiles[index] {
                            OnetTileView(
                                emoji: OnetTileFace.emoji(for: kind),
                                width: width,
                                height: height,
                                highlight: highlight(for: index),
                                isWrong: game.wrongPair[player]?.contains(index) == true
                            )
                            .position(center(OnetPoint(row: index / columns, column: index % columns), width: width, height: height))
                            .onTapGesture { onTap(index) }
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }

                    if let flash {
                        Path { path in
                            let points = flash.path.map { center($0, width: width, height: height) }
                            guard let first = points.first else { return }
                            path.move(to: first)
                            points.dropFirst().forEach { path.addLine(to: $0) }
                        }
                        .stroke(Theme.playerColor(flash.event.player), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .shadow(color: Theme.playerColor(flash.event.player).opacity(0.5), radius: 4)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                }
                .frame(width: content.width, height: content.height)
                .animation(.spring(duration: 0.3), value: game.tileIDs)
                .animation(.easeOut(duration: 0.2), value: flash)
                // Center the board when it is smaller than the viewport.
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        zoom = min(2.5, max(0.8, zoomAtGestureStart * value.magnification))
                    }
                    .onEnded { _ in zoomAtGestureStart = zoom }
            )
        }
        .background(Theme.Tile.board)
        .task(id: game.lastMatch?.serial) {
            guard let match = game.lastMatch else { return }
            flash = match
            try? await Task.sleep(for: .milliseconds(450))
            if flash == match { flash = nil }
        }
    }

    private var placedTiles: [(id: Int, cell: Int)] {
        game.tileIDs.indices.compactMap { cell in game.tileIDs[cell].map { (id: $0, cell: cell) } }
    }

    private func highlight(for index: Int) -> Color? {
        selected.contains(index) ? Theme.playerColor(player) : nil
    }

    /// Board point → position; row/column -1 and rows/columns are the outer margin.
    private func center(_ point: OnetPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(point.column) + 1) * width, y: (CGFloat(point.row) + 1) * height)
    }
}

/// A raised cream tile with an emoji face.
private struct OnetTileView: View, Equatable {
    let emoji: String
    let width: CGFloat
    let height: CGFloat
    let highlight: Color?
    let isWrong: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.16, style: .continuous)
        Text(emoji)
            .font(.system(size: min(width, height) * 0.7))
            .frame(width: width - 3, height: height - 6)
            .background(shape.fill(Theme.Tile.face))
            .background(shape.fill(Theme.Tile.edge).offset(y: 3))
            .overlay {
                if let color = isWrong ? Theme.danger : highlight {
                    shape.stroke(color, lineWidth: 3)
                }
            }
            .scaleEffect(highlight != nil ? 1.08 : 1)
            .offset(y: highlight != nil ? -2 : 0)
            .animation(.spring(duration: 0.2), value: highlight)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
    }
}

/// Game-list / setup icon: two matching tiles linked by a line around a third.
struct OnetArtwork: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let tile = CGSize(width: side * 0.25, height: side * 0.3)
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: side * 0.21, y: side * 0.44))
                    path.addLine(to: CGPoint(x: side * 0.21, y: side * 0.18))
                    path.addLine(to: CGPoint(x: side * 0.79, y: side * 0.18))
                    path.addLine(to: CGPoint(x: side * 0.79, y: side * 0.44))
                }
                .stroke(.white, style: StrokeStyle(lineWidth: side * 0.045, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)

                artworkTile("🇻🇳", size: tile, side: side).position(x: side * 0.21, y: side * 0.6)
                artworkTile("🇯🇵", size: tile, side: side).position(x: side * 0.5, y: side * 0.6)
                artworkTile("🇻🇳", size: tile, side: side).position(x: side * 0.79, y: side * 0.6)
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }

    private func artworkTile(_ emoji: String, size: CGSize, side: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.05, style: .continuous)
        return Text(emoji)
            .font(.system(size: size.width * 0.6))
            .frame(width: size.width, height: size.height)
            .background(shape.fill(Theme.Tile.face))
            .background(shape.fill(Theme.Tile.edge).offset(y: side * 0.02))
            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
    }
}
