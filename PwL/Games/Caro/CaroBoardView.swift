import SwiftUI

/// A window onto the (large) squared-paper board. Only the visible squares are drawn,
/// so a 100×100 board stays light. Drag to move, pinch to zoom, tap to play.
/// When a move lands off-screen (your love's), the view jumps to it.
struct CaroBoardView: View {
    let game: CaroGame
    let onTap: (Int) -> Void

    private static let cellRange: ClosedRange<CGFloat> = 16...64
    /// Points per square.
    @State private var cell: CGFloat = 34
    @State private var cellAtGestureStart: CGFloat?
    /// Board point (in squares) shown at the middle of the view.
    @State private var center = CGPoint(x: 50, y: 50)
    @State private var centerAtDragStart: CGPoint?
    @State private var viewSize: CGSize = .zero

    private var size: Int { game.config.size }

    var body: some View {
        Canvas { context, canvasSize in
            draw(in: &context, size: canvasSize)
        }
        .background(Theme.Paper.sheet)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self, of: \.size) { viewSize = $0 }
        .onTapGesture { location in
            let point = boardPoint(for: location)
            let column = Int(point.x.rounded(.down)), row = Int(point.y.rounded(.down))
            guard (0..<size).contains(column), (0..<size).contains(row) else { return }
            onTap(row * size + column)
        }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    let start = centerAtDragStart ?? center
                    centerAtDragStart = start
                    center = clamped(CGPoint(
                        x: start.x - value.translation.width / cell,
                        y: start.y - value.translation.height / cell
                    ))
                }
                .onEnded { _ in centerAtDragStart = nil }
                .simultaneously(with: MagnifyGesture()
                    .onChanged { value in
                        let start = cellAtGestureStart ?? cell
                        cellAtGestureStart = start
                        cell = min(Self.cellRange.upperBound, max(Self.cellRange.lowerBound, start * value.magnification))
                    }
                    .onEnded { _ in cellAtGestureStart = nil })
        )
        .overlay(alignment: .bottomTrailing) {
            if game.lastMove != nil {
                CircleIconButton(systemName: "scope", accessibilityLabel: "Go to last move") {
                    if let last = game.lastMove { focus(on: last) }
                }
                .padding(Theme.Spacing.s)
            }
        }
        .onAppear { center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2) }
        .onChange(of: game.lastMove) { _, last in
            guard let last else {
                center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
                return
            }
            if !isVisible(last) { focus(on: last) }
        }
        .accessibilityLabel("Caro board, \(size) by \(size)")
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, size canvasSize: CGSize) {
        let origin = CGPoint(x: canvasSize.width / 2 - center.x * cell, y: canvasSize.height / 2 - center.y * cell)
        let firstColumn = max(0, Int(((0 - origin.x) / cell).rounded(.down)))
        let lastColumn = min(size - 1, Int(((canvasSize.width - origin.x) / cell).rounded(.down)))
        let firstRow = max(0, Int(((0 - origin.y) / cell).rounded(.down)))
        let lastRow = min(size - 1, Int(((canvasSize.height - origin.y) / cell).rounded(.down)))
        guard firstColumn <= lastColumn, firstRow <= lastRow else { return }

        // Outside the board: slightly darker so the edge is visible.
        let boardRect = CGRect(x: origin.x, y: origin.y, width: CGFloat(size) * cell, height: CGFloat(size) * cell)
        context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(Theme.Paper.rule.opacity(0.35)))
        context.fill(Path(boardRect), with: .color(Theme.Paper.sheet))

        var grid = Path()
        let top = max(0, boardRect.minY), bottom = min(canvasSize.height, boardRect.maxY)
        let left = max(0, boardRect.minX), right = min(canvasSize.width, boardRect.maxX)
        for column in firstColumn...(lastColumn + 1) {
            let x = origin.x + CGFloat(column) * cell
            grid.move(to: CGPoint(x: x, y: top))
            grid.addLine(to: CGPoint(x: x, y: bottom))
        }
        for row in firstRow...(lastRow + 1) {
            let y = origin.y + CGFloat(row) * cell
            grid.move(to: CGPoint(x: left, y: y))
            grid.addLine(to: CGPoint(x: right, y: y))
        }
        context.stroke(grid, with: .color(Theme.Paper.rule), lineWidth: 1)

        func centerPoint(_ index: Int) -> CGPoint {
            CGPoint(x: origin.x + (CGFloat(index % size) + 0.5) * cell, y: origin.y + (CGFloat(index / size) + 0.5) * cell)
        }

        if let last = game.lastMove, game.winningLine.isEmpty, let owner = game.cells[last] {
            let p = centerPoint(last)
            let rect = CGRect(x: p.x - cell / 2 + 1, y: p.y - cell / 2 + 1, width: cell - 2, height: cell - 2)
            context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.18), with: .color(Theme.playerColor(owner).opacity(0.14)))
        }

        let marks = [0, 1].map { player in
            context.resolve(
                Text(game.mark(of: player))
                    .font(.system(size: cell * 0.72, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.playerColor(player))
            )
        }
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                let index = row * size + column
                if let owner = game.cells[index] {
                    context.draw(marks[owner], at: centerPoint(index))
                }
            }
        }

        if let first = game.winningLine.first, let last = game.winningLine.last {
            var line = Path()
            line.move(to: centerPoint(first))
            line.addLine(to: centerPoint(last))
            context.stroke(
                line,
                with: .color(Theme.playerColor(game.winner ?? 0)),
                style: StrokeStyle(lineWidth: max(3, cell * 0.12), lineCap: .round)
            )
        }
    }

    // MARK: Geometry

    private func boardPoint(for location: CGPoint) -> CGPoint {
        CGPoint(
            x: center.x + (location.x - viewSize.width / 2) / cell,
            y: center.y + (location.y - viewSize.height / 2) / cell
        )
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        let limit = CGFloat(size)
        return CGPoint(x: min(limit, max(0, point.x)), y: min(limit, max(0, point.y)))
    }

    /// Is the square comfortably inside the view (not right at the edge)?
    private func isVisible(_ index: Int) -> Bool {
        let halfWidth = viewSize.width / 2 / cell - 1, halfHeight = viewSize.height / 2 / cell - 1
        let x = CGFloat(index % size) + 0.5, y = CGFloat(index / size) + 0.5
        return abs(x - center.x) < halfWidth && abs(y - center.y) < halfHeight
    }

    private func focus(on index: Int) {
        center = CGPoint(x: CGFloat(index % size) + 0.5, y: CGFloat(index / size) + 0.5)
    }
}

/// Game-list / setup icon: a little grid with X's, O's and a winning stroke.
struct CaroArtwork: View {
    /// (mark, column, row) on a 4×4 grid.
    private let marks: [(String, Int, Int)] = [
        ("X", 0, 0), ("O", 2, 0), ("X", 1, 1), ("O", 3, 1), ("X", 2, 2), ("O", 0, 3), ("X", 3, 3),
    ]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let inset = side * 0.14
            let cell = (side - inset * 2) / 4
            ZStack(alignment: .topLeading) {
                Path { path in
                    for i in 1..<4 {
                        let p = inset + CGFloat(i) * cell
                        path.move(to: CGPoint(x: p, y: inset))
                        path.addLine(to: CGPoint(x: p, y: side - inset))
                        path.move(to: CGPoint(x: inset, y: p))
                        path.addLine(to: CGPoint(x: side - inset, y: p))
                    }
                }
                .stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: side * 0.02, lineCap: .round))

                ForEach(marks.indices, id: \.self) { i in
                    let m = marks[i]
                    Text(m.0)
                        .font(.system(size: cell * 0.78, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .position(x: inset + (CGFloat(m.1) + 0.5) * cell, y: inset + (CGFloat(m.2) + 0.5) * cell)
                }

                // Winning diagonal through the X's.
                Path { path in
                    path.move(to: CGPoint(x: inset + cell * 0.3, y: inset + cell * 0.3))
                    path.addLine(to: CGPoint(x: side - inset - cell * 0.3, y: side - inset - cell * 0.3))
                }
                .stroke(.white, style: StrokeStyle(lineWidth: side * 0.045, lineCap: .round))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }
}
