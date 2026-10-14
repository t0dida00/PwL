import SwiftUI

/// Hand-built storybook illustrations for the Seek It scenes, drawn on the fixed
/// `SeekItCanvas` (1800 × 800). Furniture lines up with the regions in `SeekItCatalog`
/// (same coordinates), so objects sit on shelves, tables and floors.
struct SeekItBackground: View, Equatable {
    let scene: SeekItSceneID

    var body: some View {
        Canvas { context, _ in
            let p = ScenePainter(context: context)
            switch scene {
            case .kitchen: SeekItSceneArt.kitchen(p)
            case .livingRoom: SeekItSceneArt.livingRoom(p)
            case .attic: SeekItSceneArt.attic(p)
            case .beach: SeekItSceneArt.beach(p)
            case .garden: SeekItSceneArt.garden(p)
            case .office: SeekItSceneArt.office(p)
            }
            // Drawn mess (papers, piles, stains…) behind the real objects.
            SeekItSceneArt.mess(scene, p)
        }
        .frame(width: SeekItCanvas.width, height: SeekItCanvas.height)
        .accessibilityHidden(true)
    }
}

/// Foreground pieces (leaves, curtains, blinds' shadow) drawn over the objects on hard,
/// so some are partly hidden. Never blocks taps.
struct SeekItForeground: View, Equatable {
    let scene: SeekItSceneID

    var body: some View {
        Canvas { context, _ in
            SeekItSceneArt.foreground(scene, ScenePainter(context: context))
        }
        .frame(width: SeekItCanvas.width, height: SeekItCanvas.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Soft vignette that frames every scene.
struct SeekItVignette: View {
    var body: some View {
        RadialGradient(
            colors: [.clear, .clear, Theme.Scene.deepShadow],
            center: .center,
            startRadius: 300,
            endRadius: 1050
        )
        .frame(width: SeekItCanvas.width, height: SeekItCanvas.height)
        .allowsHitTesting(false)
    }
}

/// Small drawing helpers over `GraphicsContext`, in canvas points.
struct ScenePainter {
    let context: GraphicsContext

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color, r: CGFloat = 0) {
        context.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r), with: .color(color))
    }

    func grad(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ top: Color, _ bottom: Color, r: CGFloat = 0) {
        let rect = CGRect(x: x, y: y, width: w, height: h)
        context.fill(
            Path(roundedRect: rect, cornerRadius: r),
            with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY))
        )
    }

    func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)), with: .color(color))
    }

    func ring(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color, _ width: CGFloat) {
        context.stroke(Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)), with: .color(color), lineWidth: width)
    }

    func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ color: Color, _ width: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x2, y: y2))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    func poly(_ points: [(CGFloat, CGFloat)], _ color: Color) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: CGPoint(x: first.0, y: first.1))
        points.dropFirst().forEach { path.addLine(to: CGPoint(x: $0.0, y: $0.1)) }
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    /// A leaf: an ellipse rotated around its base.
    func leaf(_ x: CGFloat, _ y: CGFloat, length: CGFloat, width: CGFloat, angle: Double, _ color: Color) {
        var ctx = context
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: .degrees(angle))
        ctx.fill(Path(ellipseIn: CGRect(x: 0, y: -width / 2, width: length, height: width)), with: .color(color))
    }

    /// A shelf board with a soft shadow and two brackets.
    func shelf(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
        rect(x, y + 16, w, 10, Theme.Scene.shadow)
        rect(x, y, w, 16, Theme.Scene.wood, r: 3)
        rect(x, y, w, 4, Theme.Scene.highlight, r: 2)
        for bx in [x + 40, x + w - 60] {
            poly([(bx, y + 16), (bx + 20, y + 16), (bx, y + 50)], Theme.Scene.woodDark)
        }
    }

    /// Draws with the origin moved to (x, y) and rotated by `angle` degrees.
    func rotated(_ x: CGFloat, _ y: CGFloat, _ angle: Double, _ draw: (ScenePainter) -> Void) {
        var ctx = context
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: .degrees(angle))
        draw(ScenePainter(context: ctx))
    }

    /// A sheet of paper with a few ruled lines, centered on (x, y).
    func paper(_ x: CGFloat, _ y: CGFloat, w: CGFloat = 70, h: CGFloat = 90, angle: Double) {
        rotated(x, y, angle) { p in
            p.rect(-w / 2 + 3, -h / 2 + 4, w, h, Theme.Scene.shadow, r: 2)
            p.rect(-w / 2, -h / 2, w, h, Theme.Scene.paper, r: 2)
            for i in 1...4 {
                let ly = -h / 2 + h * CGFloat(i) / 5
                p.line(-w / 2 + 8, ly, w / 2 - 8 - CGFloat(i % 2) * 14, ly, Theme.Scene.tileLine, 2)
            }
        }
    }

    /// Books lying flat, stacked up from `baseline`.
    func bookStack(_ x: CGFloat, baseline: CGFloat, count: Int, width: CGFloat = 110) {
        let colors = [Theme.Scene.fabric, Theme.Scene.rug, Theme.Scene.leaf, Theme.Scene.sun, Theme.Scene.woodDark, Theme.Scene.sea]
        for i in 0..<count {
            let w = width - CGFloat((i * 13) % 30)
            let dx = CGFloat((i * 17) % 21) - 10
            rect(x - w / 2 + dx, baseline - CGFloat(i + 1) * 18, w, 17, colors[(i + Int(x)) % colors.count], r: 3)
            rect(x - w / 2 + dx + 6, baseline - CGFloat(i + 1) * 18 + 3, w - 12, 3, Theme.Scene.paper.opacity(0.8))
        }
    }

    /// Plates stacked from `baseline`.
    func plateStack(_ x: CGFloat, baseline: CGFloat, count: Int) {
        for i in 0..<count {
            let y = baseline - CGFloat(i) * 9 - 6
            oval(x, y + 3, 120, 18, Theme.Scene.shadow)
            oval(x, y, 120, 16, Theme.Scene.paper)
            ring(x, y, 120, 16, Theme.Scene.tileLine, 2)
        }
    }

    /// A soft heap of cloth (laundry, blanket, towel) sitting on `baseline`.
    func clothHeap(_ x: CGFloat, baseline: CGFloat, width: CGFloat, _ color: Color, _ shade: Color) {
        oval(x, baseline - 4, width * 1.05, 26, Theme.Scene.shadow)
        oval(x - width * 0.22, baseline - width * 0.16, width * 0.6, width * 0.34, color)
        oval(x + width * 0.2, baseline - width * 0.14, width * 0.62, width * 0.3, shade)
        oval(x, baseline - width * 0.26, width * 0.5, width * 0.32, color)
        line(x - width * 0.2, baseline - width * 0.28, x + width * 0.15, baseline - width * 0.18, shade, 4)
    }

    /// A cardboard box sitting on `baseline`.
    func box(_ x: CGFloat, baseline: CGFloat, w: CGFloat, h: CGFloat, angle: Double = 0) {
        rotated(x, baseline - h / 2, angle) { p in
            p.rect(-w / 2 + 6, -h / 2 + 6, w, h, Theme.Scene.shadow, r: 4)
            p.rect(-w / 2, -h / 2, w, h, Theme.Scene.cork, r: 4)
            p.rect(-w / 2, -h / 2, w, h * 0.22, Theme.Scene.woodLight, r: 4)
            p.rect(-8, -h / 2, 16, h, Theme.Scene.sand.opacity(0.7))
        }
    }

    /// A ring-shaped stain (coffee cup, water).
    func stain(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: Color) {
        ring(x, y, size, size * 0.45, color, 5)
        oval(x + size * 0.3, y + 4, size * 0.2, size * 0.1, color)
    }

    /// A crumpled paper ball.
    func paperBall(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat) {
        oval(x + 3, y + size * 0.4, size * 1.1, size * 0.3, Theme.Scene.shadow)
        oval(x, y, size, size * 0.9, Theme.Scene.paper)
        line(x - size * 0.3, y - size * 0.1, x + size * 0.2, y + size * 0.15, Theme.Scene.tileLine, 2)
        line(x - size * 0.1, y - size * 0.3, x + size * 0.25, y - size * 0.05, Theme.Scene.tileLine, 2)
    }

    func vignetteCorners(_ color: Color) {
        oval(0, 0, 500, 400, color)
        oval(1800, 0, 500, 400, color)
    }
}

enum SeekItSceneArt {
    static let w = SeekItCanvas.width
    static let h = SeekItCanvas.height

    // MARK: Cozy Kitchen

    static func kitchen(_ p: ScenePainter) {
        let s = Theme.Scene.self
        p.rect(0, 0, w, 520, s.cream)
        // Tiled backsplash.
        p.rect(0, 300, w, 220, s.tile)
        for y in stride(from: 300.0, through: 520, by: 55) { p.line(0, y, w, y, s.tileLine, 2) }
        for (row, y) in stride(from: 300.0, to: 520, by: 55).enumerated() {
            for x in stride(from: row.isMultiple(of: 2) ? 0.0 : 27.5, through: w, by: 55) {
                p.line(x, y, x, y + 55, s.tileLine, 2)
            }
        }
        // Window with curtains.
        p.rect(744, 34, 312, 262, s.woodDark, r: 14)
        p.grad(764, 54, 272, 222, s.skyTop, s.skyBottom, r: 6)
        p.oval(980, 110, 70, 70, s.sun)
        p.oval(830, 120, 110, 40, s.cloud)
        p.oval(870, 104, 80, 40, s.cloud)
        p.rect(894, 54, 12, 222, s.woodDark)
        p.rect(764, 158, 272, 12, s.woodDark)
        p.rect(730, 284, 340, 20, s.wood, r: 4)
        p.poly([(690, 24), (790, 24), (770, 310), (680, 310)], s.fabric)
        p.poly([(1010, 24), (1110, 24), (1120, 310), (1030, 310)], s.fabric)
        for x in [715.0, 745, 1050, 1080] { p.line(x, 30, x - 6, 305, s.fabricDark, 4) }
        p.rect(680, 16, 440, 14, s.woodDark, r: 7)
        // Shelves and hanging rails.
        p.shelf(80, 200, 600)
        p.shelf(1120, 200, 600)
        for x0 in [120.0, 1130] {
            p.rect(x0, 322, 560, 8, s.metalDark, r: 4)
            for x in stride(from: x0 + 40, to: x0 + 560, by: 80) { p.line(x, 330, x, 346, s.metalDark, 3) }
        }
        // Counter with cabinets and the oven.
        p.rect(0, 540, w, 165, s.wood)
        for x in stride(from: 20.0, to: w, by: 180) where !(740...1040).contains(x + 80) {
            p.rect(x, 558, 160, 128, s.woodLight, r: 8)
            p.rect(x + 8, 566, 144, 112, s.highlight.opacity(0.4), r: 6)
            p.oval(x + 140, 622, 12, 12, s.metalDark)
        }
        p.rect(760, 552, 280, 140, s.metal, r: 12)
        p.rect(790, 586, 220, 82, s.screen, r: 10)
        p.rect(800, 596, 200, 20, s.lampGlow, r: 6)
        for x in [800.0, 860, 940, 1000] { p.oval(x, 568, 18, 18, s.metalDark) }
        p.rect(0, 518, w, 24, s.stone, r: 4)
        p.rect(0, 518, w, 6, s.highlight, r: 3)
        p.oval(840, 520, 90, 12, s.metalDark)
        p.oval(960, 520, 90, 12, s.metalDark)
        // Baseboard and planks.
        p.rect(0, 700, w, 14, s.woodDark)
        p.rect(0, 714, w, 86, s.floor)
        for y in [742.0, 772] { p.line(0, y, w, y, s.floorLine, 2) }
        for (i, x) in stride(from: 60.0, to: w, by: 220).enumerated() {
            p.line(x + (i.isMultiple(of: 2) ? 0 : 110), 714, x + (i.isMultiple(of: 2) ? 0 : 110), 742, s.floorLine, 2)
            p.line(x + 60, 742, x + 60, 772, s.floorLine, 2)
        }
    }

    // MARK: Living Room

    static func livingRoom(_ p: ScenePainter) {
        let s = Theme.Scene.self
        p.rect(0, 0, w, 560, s.wallpaper)
        for x in stride(from: 0.0, to: w, by: 64) { p.rect(x, 0, 24, 560, s.wallpaperStripe) }
        p.rect(0, 548, w, 16, s.woodDark)
        p.rect(0, 564, w, 236, s.floor)
        for y in [610.0, 660, 720] { p.line(0, y, w, y, s.floorLine, 2) }
        // Rug.
        p.oval(900, 705, 1160, 170, s.rugBorder)
        p.oval(900, 705, 1110, 140, s.rug)
        p.ring(900, 705, 980, 110, s.rugBorder.opacity(0.7), 6)
        // Bookshelf.
        p.rect(60, 70, 400, 500, s.woodDark, r: 8)
        p.rect(80, 90, 360, 470, s.wood.opacity(0.75))
        for y in [200.0, 330, 460] {
            p.rect(80, y, 360, 14, s.woodLight)
            p.rect(80, y + 14, 360, 8, s.shadow)
        }
        p.rect(80, 474, 360, 86, s.woodDark.opacity(0.6))
        p.oval(260, 517, 16, 16, s.metal)
        // Painting.
        p.rect(744, 84, 312, 214, s.woodLight, r: 6)
        p.grad(762, 102, 276, 178, s.skyTop, s.skyBottom)
        p.oval(860, 280, 320, 120, s.grassDark)
        p.oval(990, 286, 260, 110, s.grass)
        p.oval(990, 140, 40, 40, s.sun)
        // Floor lamp.
        p.oval(1230, 160, 220, 160, s.lampGlow)
        p.rect(1226, 180, 8, 390, s.metalDark)
        p.oval(1230, 572, 70, 14, s.metalDark)
        p.poly([(1180, 116), (1280, 116), (1302, 190), (1158, 190)], s.cream)
        p.rect(1158, 186, 144, 6, s.rugBorder)
        // Sofa.
        p.rect(640, 380, 520, 140, s.fabric, r: 34)
        p.rect(668, 396, 230, 104, s.fabricDark.opacity(0.35), r: 26)
        p.rect(902, 396, 230, 104, s.fabricDark.opacity(0.35), r: 26)
        p.rect(620, 494, 560, 72, s.fabricDark, r: 22)
        p.rect(598, 420, 76, 156, s.fabric, r: 26)
        p.rect(1126, 420, 76, 156, s.fabric, r: 26)
        p.rect(630, 566, 16, 22, s.woodDark)
        p.rect(1154, 566, 16, 22, s.woodDark)
        // Coffee table.
        p.oval(900, 732, 420, 26, s.shadow)
        p.rect(700, 640, 400, 18, s.woodLight, r: 6)
        p.rect(722, 658, 14, 70, s.woodDark)
        p.rect(1064, 658, 14, 70, s.woodDark)
        // TV on its stand.
        p.rect(1290, 462, 460, 14, s.woodLight, r: 4)
        p.rect(1300, 476, 440, 128, s.wood, r: 6)
        p.rect(1316, 494, 196, 92, s.woodDark.opacity(0.5), r: 6)
        p.rect(1528, 494, 196, 92, s.woodDark.opacity(0.5), r: 6)
        p.rect(1504, 432, 32, 32, s.metalDark)
        p.rect(1362, 244, 316, 196, s.metalDark, r: 14)
        p.grad(1374, 256, 292, 172, s.screen, s.nightBottom, r: 8)
        p.poly([(1390, 262), (1460, 262), (1400, 330)], s.highlight.opacity(0.4))
    }

    // MARK: Grandma's Attic

    static func attic(_ p: ScenePainter) {
        let s = Theme.Scene.self
        p.rect(0, 0, w, 690, s.atticWall)
        for x in stride(from: 0.0, to: w, by: 90) { p.line(x, 0, x, 690, s.woodGrain, 3) }
        // Light from the round window.
        p.poly([(840, 200), (960, 200), (1240, 790), (560, 790)], s.lampGlow.opacity(0.6))
        // Sloped roof and beams.
        p.poly([(0, 0), (520, 0), (0, 360)], s.woodDark)
        p.poly([(1280, 0), (w, 0), (w, 360)], s.woodDark)
        p.rect(0, 56, w, 28, s.woodDark)
        p.rect(596, 84, 30, 606, s.woodDark)
        p.rect(1176, 84, 30, 606, s.woodDark)
        p.line(611, 84, 900, 270, s.woodDark, 16)
        // Round window.
        p.oval(900, 170, 216, 216, s.woodLight)
        p.context.fill(
            Path(ellipseIn: CGRect(x: 808, y: 78, width: 184, height: 184)),
            with: .linearGradient(Gradient(colors: [s.nightTop, s.nightBottom]), startPoint: CGPoint(x: 900, y: 78), endPoint: CGPoint(x: 900, y: 262))
        )
        p.oval(940, 130, 44, 44, s.moon)
        p.rect(894, 78, 12, 184, s.woodLight)
        p.rect(808, 164, 184, 12, s.woodLight)
        // Cobwebs.
        for (cx, cy, flip) in [(626.0, 84.0, 1.0), (1176.0, 84.0, -1.0)] {
            for angle in stride(from: 0.0, through: 90, by: 22.5) {
                let rad = angle * .pi / 180
                p.line(cx, cy, cx + flip * cos(rad) * 120, cy + sin(rad) * 120, s.cobweb, 2)
            }
            for r in [40.0, 75, 110] {
                var arc = Path()
                arc.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(flip > 0 ? 0 : 90), endAngle: .degrees(flip > 0 ? 90 : 180), clockwise: false)
                p.context.stroke(arc, with: .color(s.cobweb), lineWidth: 2)
            }
        }
        // Shelf.
        p.shelf(120, 300, 480)
        // Floor.
        p.rect(0, 690, w, 110, s.floor)
        for y in [720.0, 755] { p.line(0, y, w, y, s.floorLine, 2) }
        // Trunk A.
        p.oval(320, 650, 440, 30, s.shadow)
        p.rect(120, 488, 400, 158, s.woodDark, r: 10)
        p.rect(110, 470, 420, 24, s.wood, r: 10)
        for x in [170.0, 450] { p.rect(x, 470, 18, 176, s.metal.opacity(0.8)) }
        p.rect(300, 520, 40, 34, s.sun.opacity(0.9), r: 4)
        // Crates.
        p.oval(900, 646, 360, 26, s.shadow)
        p.rect(740, 510, 320, 132, s.woodLight, r: 4)
        p.rect(760, 420, 280, 92, s.woodLight, r: 4)
        for y in [552.0, 596, 466] { p.line(y == 466 ? 760 : 740, y, y == 466 ? 1040 : 1060, y, s.woodGrain, 4) }
        p.line(740, 510, 1060, 640, s.woodGrain, 6)
        p.line(760, 420, 1040, 510, s.woodGrain, 6)
        // Trunk B.
        p.oval(1450, 660, 440, 30, s.shadow)
        p.rect(1250, 506, 400, 150, s.fabricDark, r: 12)
        p.rect(1240, 490, 420, 24, s.fabric, r: 10)
        for x in [1300.0, 1580] { p.rect(x, 490, 18, 166, s.woodDark) }
    }

    // MARK: Beach Day

    static func beach(_ p: ScenePainter) {
        let s = Theme.Scene.self
        p.grad(0, 0, w, 400, s.skyTop, s.skyBottom)
        p.oval(1500, 110, 220, 220, s.sun.opacity(0.35))
        p.oval(1500, 110, 140, 140, s.sun)
        for (x, y) in [(300.0, 110.0), (820, 70), (1180, 170)] {
            p.oval(x, y, 200, 60, s.cloud)
            p.oval(x - 50, y - 18, 110, 60, s.cloud)
            p.oval(x + 40, y - 26, 120, 70, s.cloud)
        }
        // Sea.
        p.grad(0, 380, w, 150, s.seaDeep, s.sea)
        for (i, y) in [418.0, 458, 498].enumerated() {
            for x in stride(from: Double(i * 70), to: w, by: 210) {
                var wave = Path()
                wave.move(to: CGPoint(x: x, y: y))
                wave.addQuadCurve(to: CGPoint(x: x + 120, y: y), control: CGPoint(x: x + 60, y: y - 18))
                p.context.stroke(wave, with: .color(s.foam), lineWidth: 4)
            }
        }
        // Sand.
        p.rect(0, 520, w, 280, s.sand)
        p.rect(0, 520, w, 34, s.sandDark)
        for (x, y) in [(200.0, 600.0), (700, 660), (1250, 610), (1600, 700), (480, 760)] {
            var ripple = Path()
            ripple.move(to: CGPoint(x: x, y: y))
            ripple.addQuadCurve(to: CGPoint(x: x + 160, y: y), control: CGPoint(x: x + 80, y: y - 14))
            p.context.stroke(ripple, with: .color(s.sandDark), lineWidth: 3)
        }
        // Towel.
        p.poly([(300, 700), (620, 680), (640, 782), (320, 798)], s.rug)
        for t in [0.25, 0.5, 0.75] {
            p.line(300 + 320 * t, 700 - 20 * t, 320 + 320 * t, 798 - 16 * t, s.cream, 10)
        }
        // Sandcastle.
        p.rect(950, 560, 120, 70, s.sandDark, r: 4)
        p.rect(980, 520, 60, 44, s.sandDark, r: 4)
        for x in [950.0, 990, 1030] { p.rect(x, 548, 22, 14, s.sandDark) }
        p.line(1010, 520, 1010, 488, s.woodDark, 3)
        p.poly([(1010, 488), (1040, 496), (1010, 504)], s.fabric)
        // Umbrella.
        p.oval(1420, 735, 300, 34, s.shadow)
        p.line(1392, 430, 1406, 735, s.woodLight, 10)
        var canopy = Path()
        canopy.addArc(center: CGPoint(x: 1392, y: 470), radius: 190, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        canopy.closeSubpath()
        p.context.fill(canopy, with: .color(s.fabric))
        for start in [200.0, 260, 320] {
            var wedge = Path()
            wedge.move(to: CGPoint(x: 1392, y: 470))
            wedge.addArc(center: CGPoint(x: 1392, y: 470), radius: 190, startAngle: .degrees(start), endAngle: .degrees(start + 30), clockwise: false)
            wedge.closeSubpath()
            p.context.fill(wedge, with: .color(s.cream))
        }
        // Palm tree.
        var trunk = Path()
        trunk.move(to: CGPoint(x: 90, y: 800))
        trunk.addQuadCurve(to: CGPoint(x: 210, y: 250), control: CGPoint(x: 100, y: 500))
        trunk.addLine(to: CGPoint(x: 238, y: 256))
        trunk.addQuadCurve(to: CGPoint(x: 140, y: 800), control: CGPoint(x: 140, y: 500))
        trunk.closeSubpath()
        p.context.fill(trunk, with: .color(s.woodLight))
        for (i, y) in stride(from: 300.0, to: 780, by: 40).enumerated() {
            p.line(120 + Double(i) * -1, y, 160 - Double(i) * 3, y + 6, s.woodGrain, 4)
        }
        for angle in [-160.0, -125, -90, -55, -20, 15] {
            p.leaf(222, 252, length: 230, width: 60, angle: angle, s.leaf)
        }
        p.oval(222, 262, 46, 46, s.woodDark)
    }

    // MARK: Secret Garden

    static func garden(_ p: ScenePainter) {
        let s = Theme.Scene.self
        p.grad(0, 0, w, 300, s.skyTop, s.skyBottom)
        p.oval(1580, 90, 120, 120, s.sun)
        for x in stride(from: 0.0, through: w, by: 120) {
            p.oval(x, 230, 200, 140, s.leafDark)
        }
        // Hedge wall with a bumpy top.
        p.rect(0, 250, w, 175, s.leaf)
        for x in stride(from: 0.0, through: w, by: 90) { p.oval(x, 252, 120, 70, s.leaf) }
        for (x, y) in [(150.0, 330.0), (420, 300), (700, 360), (1100, 320), (1380, 370), (1650, 310)] {
            p.oval(x, y, 140, 60, s.leafDark.opacity(0.45))
        }
        // Lawn.
        p.grad(0, 420, w, 380, s.grass, s.grassDark)
        // Stone path.
        p.poly([(860, 420), (940, 420), (1160, 800), (640, 800)], s.stone)
        for (x, y) in [(900.0, 470.0), (870, 560), (950, 610), (880, 690), (1000, 740), (780, 760)] {
            p.oval(x, y, 90, 36, s.stoneDark.opacity(0.5))
        }
        // Fountain.
        p.oval(900, 500, 330, 90, s.stoneDark)
        p.oval(900, 474, 300, 70, s.stone)
        p.oval(900, 474, 250, 46, s.water)
        p.rect(886, 330, 28, 140, s.stone)
        p.oval(900, 332, 130, 30, s.stoneDark)
        for dx in [-50.0, 50] {
            var spray = Path()
            spray.move(to: CGPoint(x: 900, y: 320))
            spray.addQuadCurve(to: CGPoint(x: 900 + dx * 1.6, y: 460), control: CGPoint(x: 900 + dx, y: 260))
            p.context.stroke(spray, with: .color(s.water), lineWidth: 6)
        }
        // Tree on the left.
        p.rect(78, 260, 64, 420, s.woodDark, r: 10)
        for (x, y, d) in [(110.0, 210.0, 260.0), (40, 290, 180), (190, 280, 190), (110, 330, 200)] {
            p.oval(x, y, d, d * 0.85, s.leafDark)
        }
        p.oval(80, 190, 120, 90, s.leaf.opacity(0.6))
        // Flower beds.
        for (i, x) in stride(from: 240.0, to: 760, by: 46).enumerated() {
            p.oval(x, 452 + Double(i % 2) * 10, 22, 22, i.isMultiple(of: 3) ? s.sun : s.petal)
        }
        for (i, x) in stride(from: 1060.0, to: 1720, by: 46).enumerated() {
            p.oval(x, 452 + Double(i % 2) * 10, 22, 22, i.isMultiple(of: 3) ? s.petal : s.fabric)
        }
        // Picnic blanket.
        p.poly([(1220, 612), (1640, 600), (1662, 724), (1198, 734)], s.fabric)
        for t in stride(from: 0.125, to: 1, by: 0.25) {
            p.line(1220 + 420 * t, 612 - 12 * t, 1198 + 464 * t, 734 - 10 * t, s.cream.opacity(0.8), 14)
            p.line(1220 - 22 * t, 612 + 122 * t, 1640 + 22 * t, 600 + 124 * t, s.cream.opacity(0.6), 12)
        }
    }

    // MARK: Detective Office

    static func office(_ p: ScenePainter) {
        let s = Theme.Scene.self
        p.rect(0, 0, w, 712, s.officeWall)
        p.rect(0, 500, w, 212, s.wainscot)
        for x in stride(from: 30.0, to: w, by: 200) { p.rect(x, 522, 170, 170, s.woodDark.opacity(0.5), r: 6) }
        p.rect(0, 496, w, 10, s.wood)
        // Window with blinds.
        p.rect(1244, 54, 472, 342, s.woodLight, r: 8)
        p.grad(1262, 72, 436, 306, s.nightTop, s.nightBottom)
        for y in stride(from: 76.0, to: 372, by: 24) { p.rect(1262, y, 436, 14, s.metal.opacity(0.85)) }
        p.rect(1236, 384, 488, 16, s.woodLight, r: 4)
        // Corkboard with pinned clues and red string.
        p.rect(118, 66, 504, 268, s.woodDark, r: 8)
        p.rect(134, 82, 472, 236, s.cork)
        let pins: [(CGFloat, CGFloat)] = [(200, 120), (380, 110), (540, 150), (260, 260), (470, 270)]
        for (x, y) in pins { p.poly([(x - 34, y - 6), (x + 36, y - 2), (x + 30, y + 52), (x - 38, y + 46)], s.paper) }
        for (a, b) in [(0, 1), (1, 2), (0, 3), (3, 4), (2, 4)] {
            p.line(pins[a].0, pins[a].1, pins[b].0, pins[b].1, s.string, 3)
        }
        for (x, y) in pins { p.oval(x, y, 14, 14, s.string) }
        // Wall shelf.
        p.shelf(690, 260, 480)
        // Filing cabinet.
        p.oval(210, 708, 300, 20, s.deepShadow)
        p.rect(80, 360, 260, 344, s.metal, r: 8)
        for y in [378.0, 488, 598] {
            p.rect(96, y, 228, 96, s.metalDark.opacity(0.35), r: 6)
            p.rect(180, y + 40, 60, 12, s.metalDark, r: 6)
        }
        // Desk.
        p.oval(900, 708, 980, 30, s.deepShadow)
        p.rect(470, 484, 260, 220, s.wood, r: 6)
        p.rect(1070, 484, 260, 220, s.wood, r: 6)
        p.rect(730, 484, 340, 150, s.woodDark)
        for y in [500.0, 568, 636] {
            p.rect(488, y, 224, 56, s.woodLight.opacity(0.5), r: 4)
            p.rect(1088, y, 224, 56, s.woodLight.opacity(0.5), r: 4)
        }
        p.rect(450, 462, 900, 24, s.woodDark, r: 6)
        p.rect(450, 462, 900, 5, s.highlight, r: 3)
        // Desk lamp glow.
        p.oval(1290, 430, 260, 120, s.lampGlow)
        p.line(1290, 462, 1270, 380, s.metalDark, 8)
        p.line(1270, 380, 1320, 330, s.metalDark, 8)
        p.poly([(1296, 320), (1360, 320), (1380, 360), (1276, 360)], s.leafDark)
        // Floor.
        p.rect(0, 708, w, 10, s.woodDark)
        p.rect(0, 718, w, 82, s.carpet)
    }

    // MARK: Mess (drawn clutter that makes hunting harder)

    static func mess(_ scene: SeekItSceneID, _ p: ScenePainter) {
        let s = Theme.Scene.self
        // Same scatter on every device: seeded by the room.
        var rng = SeededGenerator(seed: UInt64(scene.rawValue.unicodeScalars.reduce(7) { $0 &* 31 &+ UInt64($1.value) }))
        func scatter(_ count: Int, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>, _ draw: (CGFloat, CGFloat, Double) -> Void) {
            for _ in 0..<count {
                draw(CGFloat.random(in: x, using: &rng), CGFloat.random(in: y, using: &rng), Double.random(in: -40...40, using: &rng))
            }
        }

        switch scene {
        case .kitchen:
            p.bookStack(560, baseline: 200, count: 4, width: 100)          // cookbooks
            for x in [1200.0, 1260, 1660] {                                  // spice jars
                p.rect(x - 18, 156, 36, 44, s.glass, r: 8)
                p.rect(x - 18, 150, 36, 12, s.fabricDark, r: 4)
            }
            p.paper(720, 380, angle: -8)                                     // recipe notes on the tiles
            p.paper(1085, 420, w: 60, h: 76, angle: 10)
            p.plateStack(170, baseline: 522, count: 5)
            p.plateStack(1420, baseline: 522, count: 3)
            p.rotated(470, 510, -6) { q in q.rect(-90, -14, 180, 26, s.woodLight, r: 8) }   // cutting board
            p.oval(1560, 516, 160, 16, s.paper.opacity(0.9))                // flour spill
            p.rect(330, 540, 70, 110, s.tile, r: 6)                          // dish towel over the counter
            for y in [560.0, 590, 620] { p.line(334, y, 396, y, s.fabric, 5) }
            p.oval(780, 770, 420, 50, s.rug.opacity(0.8))                    // floor mat
            scatter(26, x: 60...1740, y: 724...792) { x, y, _ in p.oval(x, y, 8, 5, s.woodLight) }  // crumbs
            p.oval(1250, 760, 120, 22, s.paper.opacity(0.85))                // more flour on the floor
        case .livingRoom:
            p.bookStack(200, baseline: 200, count: 3)
            p.bookStack(330, baseline: 330, count: 5, width: 90)
            p.bookStack(160, baseline: 460, count: 2)
            p.poly([(1130, 420), (1210, 430), (1220, 560), (1150, 600), (1120, 520)], s.rug)   // throw over the arm
            p.clothHeap(300, baseline: 780, width: 200, s.fabric, s.fabricDark)                  // cushions
            p.clothHeap(1600, baseline: 780, width: 260, s.rug, s.sea)                            // laundry
            p.paper(840, 720, w: 90, h: 64, angle: 18)                       // magazines on the rug
            p.paper(980, 740, w: 90, h: 64, angle: -24)
            p.paper(905, 630, w: 80, h: 56, angle: 6)
            p.stain(1000, 646, 40, s.woodDark.opacity(0.5))
            scatter(6, x: 80...1700, y: 710...790) { x, y, a in p.paper(x, y, w: 40, h: 30, angle: a) }
        case .attic:
            p.box(560, baseline: 700, w: 130, h: 110, angle: -4)
            p.box(660, baseline: 700, w: 110, h: 90, angle: 6)
            p.box(600, baseline: 600, w: 100, h: 80, angle: -10)
            p.box(1720, baseline: 720, w: 150, h: 120, angle: 3)
            p.clothHeap(320, baseline: 478, width: 220, s.rug, s.sea)         // old blanket on the trunk
            p.clothHeap(1450, baseline: 496, width: 200, s.wallpaper, s.wallpaperStripe)
            p.bookStack(470, baseline: 300, count: 5, width: 90)
            p.rotated(1120, 640, 14) { q in                                   // picture frame leaning on the post
                q.rect(-60, -80, 120, 160, s.woodLight, r: 6)
                q.rect(-46, -66, 92, 132, s.nightBottom, r: 4)
            }
            scatter(10, x: 60...1740, y: 700...790) { x, y, a in p.paper(x, y, w: 46, h: 58, angle: a) }
        case .beach:
            for i in 0..<12 {                                                 // footprints
                let x = 500 + CGFloat(i) * 70, y = 780 - CGFloat(i) * 16
                p.oval(x, y + (i.isMultiple(of: 2) ? 0 : 18), 22, 34, s.sandDark)
            }
            p.poly([(1500, 620), (1760, 600), (1780, 680), (1520, 700)], s.fabric)   // second towel
            for t in [0.33, 0.66] { p.line(1500 + 260 * t, 620 - 20 * t, 1520 + 260 * t, 700 - 20 * t, s.cream, 10) }
            scatter(9, x: 80...1700, y: 560...780) { x, y, a in
                var weed = Path()
                weed.move(to: CGPoint(x: x, y: y))
                weed.addCurve(to: CGPoint(x: x + 80, y: y + 6), control1: CGPoint(x: x + 20, y: y - 20), control2: CGPoint(x: x + 50, y: y + 26))
                p.context.stroke(weed, with: .color(s.leafDark), lineWidth: 6)
            }
            for (x, y) in [(260.0, 640.0), (1180, 760), (760, 600)] { p.oval(x, y, 140, 40, s.sandDark) }  // sand piles
        case .garden:
            scatter(60, x: 60...1740, y: 470...790) { x, y, a in             // fallen leaves and petals
                p.rotated(x, y, a * 3) { q in q.oval(0, 0, 26, 12, [s.leafDark, s.sun, s.petal, s.woodLight][Int(abs(a)) % 4]) }
            }
            for (i, y) in [700.0, 660, 620].enumerated() {                  // stacked flower pots
                let x = 1720.0 - Double(i) * 10
                p.poly([(x - 48, y - 50), (x + 48, y - 50), (x + 36, y), (x - 36, y)], s.fabricDark)
                p.rect(x - 54, y - 58, 108, 14, s.fabric, r: 4)
            }
            var hose = Path()                                                // garden hose
            hose.move(to: CGPoint(x: 180, y: 600))
            hose.addCurve(to: CGPoint(x: 600, y: 740), control1: CGPoint(x: 420, y: 520), control2: CGPoint(x: 260, y: 800))
            hose.addCurve(to: CGPoint(x: 560, y: 640), control1: CGPoint(x: 760, y: 700), control2: CGPoint(x: 700, y: 600))
            p.context.stroke(hose, with: .color(s.leaf), lineWidth: 12)
            p.plateStack(1300, baseline: 690, count: 2)
            p.clothHeap(1560, baseline: 700, width: 150, s.cream, s.rugBorder)   // napkins on the blanket
        case .office:
            for (x, base) in [(560.0, 472.0), (930, 472), (1180, 472)] {     // paper piles on the desk
                for i in 0..<4 {
                    p.paper(x + CGFloat(i * 7 - 10), base - 30 - CGFloat(i) * 7, w: 120, h: 58, angle: Double(i * 5 - 8))
                }
            }
            p.stain(760, 468, 46, s.woodLight)                                // coffee rings
            p.stain(1050, 470, 38, s.woodLight)
            p.box(1500, baseline: 712, w: 160, h: 100, angle: -3)              // file boxes
            p.box(1520, baseline: 612, w: 140, h: 86, angle: 5)
            p.bookStack(1080, baseline: 260, count: 4, width: 96)
            p.bookStack(760, baseline: 260, count: 3, width: 96)
            scatter(9, x: 80...1700, y: 724...790) { x, y, _ in p.paperBall(x, y, 30) }
            scatter(7, x: 80...1700, y: 720...790) { x, y, a in p.paper(x, y, w: 60, h: 46, angle: a) }
        }
    }

    // MARK: Foreground occluders (hard)

    static func foreground(_ scene: SeekItSceneID, _ p: ScenePainter) {
        let s = Theme.Scene.self
        switch scene {
        case .beach, .garden:
            // Big leaves creeping in from the corners.
            for (angle, length) in [(-70.0, 300.0), (-40, 340), (-10, 280), (20, 220)] {
                p.leaf(-20, 820, length: length, width: 90, angle: angle, s.leafDark.opacity(0.92))
            }
            for (angle, length) in [(200.0, 260.0), (170, 300), (140, 240)] {
                p.leaf(1830, 820, length: length, width: 80, angle: angle, s.leaf.opacity(0.92))
            }
            for (angle, length) in [(60.0, 220.0), (100, 260), (140, 200)] {
                p.leaf(1700, -30, length: length, width: 70, angle: angle, s.leafDark.opacity(0.85))
            }
        case .office:
            // Light from the blinds falling across the room.
            for i in 0..<6 {
                let x = 300.0 + Double(i) * 180
                p.poly([(x, 0), (x + 80, 0), (x - 320, 800), (x - 400, 800)], s.lampGlow.opacity(0.7))
            }
            // A big office plant in the front-right corner.
            for (angle, length) in [(-100.0, 300.0), (-125, 340), (-150, 300), (-170, 240), (-75, 240)] {
                p.leaf(1760, 830, length: length, width: 84, angle: angle, s.leafDark.opacity(0.94))
            }
            p.rect(1680, 740, 150, 70, s.woodDark, r: 10)
        case .kitchen, .livingRoom, .attic:
            // Curtain edges and a plant in the corner.
            p.poly([(0, 0), (150, 0), (110, 800), (0, 800)], s.fabric.opacity(0.92))
            for x in [40.0, 90] { p.line(x, 0, x - 20, 800, s.fabricDark.opacity(0.7), 6) }
            p.poly([(1800, 0), (1660, 0), (1700, 800), (1800, 800)], s.fabric.opacity(0.92))
            for (angle, length) in [(-110.0, 240.0), (-80, 300), (-50, 250), (-20, 200)] {
                p.leaf(1540, 820, length: length, width: 80, angle: angle, s.leafDark.opacity(0.92))
            }
        }
    }
}

/// Game-list / setup icon: a cluttered little shelf under a magnifying glass.
struct SeekItArtwork: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(Array(["🗝️", "🧸", "🍎", "🕰️", "🎩"].enumerated()), id: \.offset) { index, emoji in
                    let spots: [(CGFloat, CGFloat, CGFloat, Double)] = [(0.22, 0.26, 0.2, -18), (0.78, 0.24, 0.2, 14), (0.22, 0.76, 0.2, 10), (0.8, 0.78, 0.18, -12), (0.5, 0.86, 0.16, 6)]
                    let spot = spots[index]
                    Text(emoji)
                        .font(.system(size: side * spot.2))
                        .rotationEffect(.degrees(spot.3))
                        .opacity(0.9)
                        .position(x: side * spot.0, y: side * spot.1)
                }
                ZStack {
                    Circle().fill(.white.opacity(0.9)).frame(width: side * 0.42, height: side * 0.42)
                    Text("🔑").font(.system(size: side * 0.22))
                    Circle().stroke(.white, lineWidth: side * 0.05).frame(width: side * 0.48, height: side * 0.48)
                    Capsule()
                        .fill(.white)
                        .frame(width: side * 0.07, height: side * 0.2)
                        .offset(y: side * 0.32)
                        .rotationEffect(.degrees(-45))
                }
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                .position(x: side * 0.5, y: side * 0.47)
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }
}
