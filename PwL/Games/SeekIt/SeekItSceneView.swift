import SwiftUI

/// The illustrated room with its objects, scaled to fit and zoomable (pinch 1–3×, drag
/// to pan). Taps are reported in canvas points (`SeekItCanvas`).
struct SeekItSceneView: View {
    let game: SeekItGame
    /// Target being hinted (glows for a moment).
    let hinted: Int?
    /// Last miss, in canvas points (shows a red ✕).
    let missMark: CGPoint?
    let onTap: (CGPoint) -> Void

    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let fit = min(geo.size.width / SeekItCanvas.width, geo.size.height / SeekItCanvas.height)
            let scale = fit * zoom
            let scaled = CGSize(width: SeekItCanvas.width * scale, height: SeekItCanvas.height * scale)

            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                SeekItRoom(game: game, hinted: hinted, missMark: missMark)
                    // A new room for every level.
                    .id(game.level.number)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: scaled.width, height: scaled.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        onTap(CGPoint(x: location.x / scale, y: location.y / scale))
                    }
                    // Center the room when it is smaller than the viewport.
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .defaultScrollAnchor(.center)
            .animation(.easeInOut(duration: 0.45), value: game.level.number)
            .onChange(of: game.level.number) {
                zoom = 1
                zoomAtGestureStart = 1
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        zoom = min(3, max(1, zoomAtGestureStart * value.magnification))
                    }
                    .onEnded { _ in zoomAtGestureStart = zoom }
            )
        }
        .background(Theme.Scene.woodDark)
        .accessibilityLabel("\(game.scene.title). \(game.targetCount - game.foundCount) objects left to find.")
    }
}

/// The full-size (1800 × 800) room: background, objects, found circles, hint, foreground.
struct SeekItRoom: View {
    let game: SeekItGame
    var hinted: Int?
    var missMark: CGPoint?

    var body: some View {
        ZStack(alignment: .topLeading) {
            SeekItBackground(scene: game.sceneID).equatable()

            ForEach(game.layout.placements, id: \.id) { placement in
                SeekItObjectView(placement: placement, foundBy: game.foundBy[placement.id])
            }

            // Papers, leaves and crumbs dropped over some objects — partly hiding them.
            SeekItFrontMess(layout: game.layout, scene: game.sceneID, count: game.level.frontMess)

            if game.level.hasOccluders {
                SeekItForeground(scene: game.sceneID).equatable()
            }

            // Circles go over the foreground so finds are always visible.
            ForEach(game.layout.targets, id: \.self) { id in
                if let finder = game.foundBy[id], let placement = game.layout.placement(id) {
                    PenCircle(color: Theme.playerColor(finder), lineWidth: 8)
                        .frame(width: placement.size * 1.45, height: placement.size * 1.3)
                        .position(placement.center)
                        .transition(.opacity)
                }
            }

            if let hinted, let placement = game.layout.placement(hinted) {
                HintGlow(size: placement.size * 1.8)
                    .position(placement.center)
                    .transition(.opacity)
            }

            if let missMark {
                Image(systemName: "xmark")
                    .font(.system(size: 64, weight: .black))
                    .foregroundStyle(Theme.danger)
                    .shadow(color: .white, radius: 4)
                    .position(missMark)
                    .transition(.scale.combined(with: .opacity))
            }

            SeekItVignette()
        }
        .frame(width: SeekItCanvas.width, height: SeekItCanvas.height, alignment: .topLeading)
        .clipped()
        .animation(.spring(duration: 0.35), value: game.foundBy)
        .animation(.easeInOut(duration: 0.25), value: hinted)
        .animation(.easeOut(duration: 0.2), value: missMark)
    }
}

/// One emoji object with a soft contact shadow when it stands on something.
private struct SeekItObjectView: View {
    let placement: SeekItPlacement
    let foundBy: Int?

    var body: some View {
        ZStack {
            if placement.standing {
                Ellipse()
                    .fill(Theme.Scene.shadow)
                    .frame(width: placement.size * 0.8, height: placement.size * 0.16)
                    .offset(y: placement.size * 0.44)
            }
            Text(placement.emoji)
                .font(.system(size: placement.size))
                .rotationEffect(.degrees(placement.rotation))
                .scaleEffect(foundBy != nil ? 1.15 : 1)
                .opacity(foundBy != nil ? 0.55 : 1)
        }
        .frame(width: placement.size * 1.2, height: placement.size * 1.2)
        .position(placement.center)
        .allowsHitTesting(false)
    }
}

/// A pulsing golden ring that points out a hinted object.
private struct HintGlow: View {
    let size: CGFloat
    @State private var pulse = false

    var body: some View {
        Circle()
            .stroke(Theme.Scene.sun, lineWidth: 12)
            .background(Circle().fill(Theme.Scene.lampGlow))
            .frame(width: size, height: size)
            .scaleEffect(pulse ? 1.15 : 0.85)
            .shadow(color: Theme.Scene.sun, radius: 20)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

/// Small bits of mess laid over objects so they're only partly visible. Seeded from the
/// layout, so both phones draw exactly the same. Each bit is smaller than the object it
/// covers and offset from its center, so nothing is fully hidden. Never blocks taps.
private struct SeekItFrontMess: View {
    let layout: SeekItLayout
    let scene: SeekItSceneID
    let count: Int

    var body: some View {
        Canvas { context, _ in
            let p = ScenePainter(context: context)
            let s = Theme.Scene.self
            let items = layout.placements
            guard !items.isEmpty else { return }
            var rng = SeededGenerator(seed: UInt64(items.count * 7919 + count) &+ UInt64(abs(Int(items[0].center.x * 31 + items[0].center.y))))
            for i in 0..<count {
                let item = items[Int.random(in: 0..<items.count, using: &rng)]
                let angle = Double.random(in: -60...60, using: &rng)
                let dx = CGFloat.random(in: -0.4...0.4, using: &rng) * item.size
                let dy = CGFloat.random(in: -0.1...0.4, using: &rng) * item.size
                let x = item.center.x + dx, y = item.center.y + dy
                let size = item.size * CGFloat.random(in: 0.35...0.6, using: &rng)
                switch scene {
                case .garden:
                    p.leaf(x, y, length: size, width: size * 0.45, angle: angle, i.isMultiple(of: 3) ? s.petal : s.leafDark)
                case .beach:
                    if i.isMultiple(of: 2) {
                        p.oval(x, y, size * 1.2, size * 0.4, s.sandDark)
                    } else {
                        p.leaf(x, y, length: size, width: size * 0.3, angle: angle, s.leafDark)
                    }
                case .kitchen:
                    if i.isMultiple(of: 3) {
                        p.paper(x, y, w: size * 0.9, h: size * 0.7, angle: angle)
                    } else {
                        p.rotated(x, y, angle) { q in q.rect(-size * 0.5, -size * 0.12, size, size * 0.24, i.isMultiple(of: 2) ? s.tile : s.fabric, r: 3) }
                    }
                case .livingRoom, .attic, .office:
                    if i.isMultiple(of: 3) {
                        p.paperBall(x, y, size * 0.6)
                    } else {
                        p.paper(x, y, w: size * 0.9, h: size * 0.65, angle: angle)
                    }
                }
            }
        }
        .frame(width: SeekItCanvas.width, height: SeekItCanvas.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
