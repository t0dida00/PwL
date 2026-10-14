import SwiftUI

/// The scattered-numbers "paper sheet". Pinch to zoom, drag to scroll on big boards.
struct NumberBoardView: View {
    let game: FindNumbersGame
    /// Whose board this is (duel halves each get their own).
    var player = 0
    let onTap: (Int) -> Void

    /// Smallest comfortable tap target, in points.
    private let minCell: CGFloat = 40
    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let board = game.board
            let fitCell = min(geo.size.width / CGFloat(board.columns), geo.size.height / CGFloat(board.rows))
            let cell = max(fitCell, minCell) * zoom
            let contentSize = CGSize(width: cell * CGFloat(board.columns), height: cell * CGFloat(board.rows))

            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    ForEach(board.tiles) { tile in
                        NumberTileView(
                            tile: tile,
                            cell: cell,
                            circleColor: game.foundBy[tile.value].map(Theme.playerColor),
                            isWrong: game.wrongValues[player] == tile.value
                        ) {
                            onTap(tile.value)
                        }
                        .position(
                            x: (CGFloat(tile.column) + 0.5) * cell,
                            y: (CGFloat(tile.row) + 0.5) * cell
                        )
                    }
                }
                .frame(width: contentSize.width, height: contentSize.height)
                // Center the sheet when it is smaller than the viewport.
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                // Ruled lines scale with the zoom, like writing on the page.
                .background { ExerciseBookPaper(lineSpacing: max(cell / 2, 18)) }
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        zoom = min(2.5, max(0.6, zoomAtGestureStart * value.magnification))
                    }
                    .onEnded { _ in zoomAtGestureStart = zoom }
            )
        }
    }
}

/// Cream page with blue ruled lines and a red margin, like a school exercise book.
struct ExerciseBookPaper: View {
    let lineSpacing: CGFloat

    var body: some View {
        Canvas { context, size in
            var rules = Path()
            var y = lineSpacing
            while y < size.height {
                rules.move(to: CGPoint(x: 0, y: y))
                rules.addLine(to: CGPoint(x: size.width, y: y))
                y += lineSpacing
            }
            context.stroke(rules, with: .color(Theme.Paper.rule), lineWidth: 1)

            var margin = Path()
            let x = min(28, size.width * 0.08)
            margin.move(to: CGPoint(x: x, y: 0))
            margin.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(margin, with: .color(Theme.Paper.margin), lineWidth: 1.5)
        }
        .background(Theme.Paper.sheet)
        .accessibilityHidden(true)
    }
}

private struct NumberTileView: View, Equatable {
    let tile: NumberTile
    let cell: CGFloat
    /// Color of the player who found it; `nil` while still unfound.
    let circleColor: Color?
    let isWrong: Bool
    let action: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tile == rhs.tile && lhs.cell == rhs.cell && lhs.circleColor == rhs.circleColor && lhs.isWrong == rhs.isWrong
    }

    private var isFound: Bool { circleColor != nil }

    private var color: Color {
        Theme.tilePalette[tile.colorIndex % Theme.tilePalette.count]
    }

    private var digits: Int { String(tile.value).count }

    private var fontSize: CGFloat {
        let digitFactor: CGFloat = switch digits {
        case 1: 0.72
        case 2: 0.6
        default: 0.44
        }
        return cell * digitFactor * CGFloat(tile.scale)
    }

    /// An oval that hugs the number, like a pen circle on paper.
    private var circleSize: CGSize {
        let textWidth = fontSize * 0.62 * CGFloat(digits)
        let width = min(cell * 0.98, max(textWidth, fontSize * 0.7) + fontSize * 0.55)
        let height = min(cell * 0.98, fontSize * 1.2)
        return CGSize(width: max(width, height * 0.9), height: height)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if let circleColor {
                    PenCircle(color: circleColor, lineWidth: max(2, fontSize * 0.08))
                        .frame(width: circleSize.width, height: circleSize.height)
                }
                Text(verbatim: "\(tile.value)")
                    .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                    .underline(tile.needsUnderline, color: isWrong ? Theme.danger : color)
                    .foregroundStyle(isWrong ? Theme.danger : color)
                    .opacity(isFound ? 0.4 : 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .scaleEffect(isWrong ? 1.15 : 1)
            }
            .rotationEffect(.degrees(tile.rotation))
            .offset(x: cell * tile.offsetX, y: cell * tile.offsetY)
            .frame(width: cell, height: cell)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFound)
        .modifier(ShakeEffect(progress: isWrong ? 1 : 0))
        .animation(.easeInOut(duration: 0.35), value: isWrong)
        .accessibilityLabel(isFound ? "\(tile.value), found" : "\(tile.value)")
    }
}

/// A hand-drawn-looking circle that "draws itself" when it appears.
private struct PenCircle: View {
    let color: Color
    let lineWidth: CGFloat
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Ellipse().fill(color.opacity(0.1))
            // Slightly more than a full loop, so the ends overlap like a real pen stroke.
            Ellipse()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-100))
            Ellipse()
                .trim(from: 0, to: max(0, progress - 1) * 1.5)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-100))
                .scaleEffect(1.06)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) { progress = 1.08 }
        }
    }
}

/// Horizontal wiggle while `progress` animates between 0 and 1.
private struct ShakeEffect: GeometryEffect {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(progress * .pi * 6) * 5, y: 0))
    }
}
