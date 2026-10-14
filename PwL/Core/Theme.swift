import SwiftUI

/// Single source of truth for colors, gradients, radii and spacing.
/// Never hard-code colors in views — add a token here instead.
enum Theme {
    // MARK: Colors
    static let rose = Color(red: 0.961, green: 0.361, blue: 0.522)
    static let plum = Color(red: 0.420, green: 0.200, blue: 0.550)
    static let peach = Color(red: 1.000, green: 0.620, blue: 0.480)
    static let lilac = Color(red: 0.720, green: 0.560, blue: 0.950)
    static let ink = Color(red: 0.200, green: 0.120, blue: 0.240)
    static let inkSoft = Color(red: 0.200, green: 0.120, blue: 0.240).opacity(0.6)
    static let surface = Color.white.opacity(0.85)
    static let danger = Color(red: 0.900, green: 0.200, blue: 0.250)
    static let success = Color(red: 0.200, green: 0.700, blue: 0.500)

    /// One color per player — used for their circles, turn banner and stats.
    static let playerColors: [Color] = [
        rose,
        Color(red: 0.180, green: 0.450, blue: 0.900),
    ]

    static func playerColor(_ index: Int) -> Color {
        playerColors[index % playerColors.count]
    }

    /// Colors used for number tiles on game boards.
    static let tilePalette: [Color] = [
        rose,
        plum,
        Color(red: 0.950, green: 0.450, blue: 0.250),
        Color(red: 0.200, green: 0.500, blue: 0.850),
        Color(red: 0.150, green: 0.600, blue: 0.550),
        Color(red: 0.750, green: 0.250, blue: 0.700),
        Color(red: 0.850, green: 0.600, blue: 0.100),
    ]

    /// Exercise-book page used behind game boards.
    enum Paper {
        static let sheet = Color(red: 1.0, green: 0.988, blue: 0.955)
        static let rule = Color(red: 0.55, green: 0.72, blue: 0.92).opacity(0.45)
        static let margin = Color(red: 0.93, green: 0.40, blue: 0.45).opacity(0.55)
    }

    /// Raised "mahjong" tiles (Onet).
    enum Tile {
        static let face = Color(red: 1.0, green: 0.95, blue: 0.88)
        static let edge = Color(red: 0.86, green: 0.70, blue: 0.56)
        static let board = Color(red: 0.42, green: 0.20, blue: 0.55).opacity(0.08)
    }

    /// Seek It scene illustration palette (storybook, flat-shaded).
    enum Scene {
        // Wood & furniture
        static let woodLight = Color(red: 0.80, green: 0.58, blue: 0.38)
        static let wood = Color(red: 0.62, green: 0.40, blue: 0.24)
        static let woodDark = Color(red: 0.42, green: 0.26, blue: 0.16)
        static let woodGrain = Color(red: 0.36, green: 0.22, blue: 0.13).opacity(0.35)
        // Walls & floors
        static let cream = Color(red: 0.99, green: 0.94, blue: 0.84)
        static let tile = Color(red: 0.86, green: 0.93, blue: 0.94)
        static let tileLine = Color(red: 0.62, green: 0.76, blue: 0.80)
        static let wallpaper = Color(red: 0.98, green: 0.86, blue: 0.86)
        static let wallpaperStripe = Color(red: 0.95, green: 0.76, blue: 0.79)
        static let atticWall = Color(red: 0.45, green: 0.32, blue: 0.27)
        static let officeWall = Color(red: 0.24, green: 0.36, blue: 0.32)
        static let wainscot = Color(red: 0.35, green: 0.22, blue: 0.16)
        static let floor = Color(red: 0.72, green: 0.50, blue: 0.32)
        static let floorLine = Color(red: 0.50, green: 0.32, blue: 0.20).opacity(0.5)
        static let carpet = Color(red: 0.55, green: 0.22, blue: 0.25)
        static let rug = Color(red: 0.55, green: 0.70, blue: 0.86)
        static let rugBorder = Color(red: 0.95, green: 0.88, blue: 0.70)
        static let stone = Color(red: 0.80, green: 0.80, blue: 0.82)
        static let stoneDark = Color(red: 0.58, green: 0.58, blue: 0.62)
        static let metal = Color(red: 0.72, green: 0.75, blue: 0.80)
        static let metalDark = Color(red: 0.40, green: 0.43, blue: 0.48)
        static let fabric = Color(red: 0.86, green: 0.42, blue: 0.48)
        static let fabricDark = Color(red: 0.66, green: 0.28, blue: 0.36)
        static let cork = Color(red: 0.80, green: 0.62, blue: 0.42)
        static let paper = Color(red: 0.98, green: 0.97, blue: 0.92)
        static let string = Color(red: 0.86, green: 0.16, blue: 0.20)
        static let screen = Color(red: 0.16, green: 0.20, blue: 0.28)
        // Outdoors
        static let skyTop = Color(red: 0.45, green: 0.72, blue: 0.96)
        static let skyBottom = Color(red: 0.82, green: 0.93, blue: 1.0)
        static let nightTop = Color(red: 0.12, green: 0.16, blue: 0.34)
        static let nightBottom = Color(red: 0.30, green: 0.34, blue: 0.56)
        static let sun = Color(red: 1.0, green: 0.84, blue: 0.36)
        static let moon = Color(red: 0.98, green: 0.96, blue: 0.82)
        static let cloud = Color.white.opacity(0.92)
        static let sea = Color(red: 0.24, green: 0.62, blue: 0.82)
        static let seaDeep = Color(red: 0.14, green: 0.44, blue: 0.68)
        static let foam = Color.white.opacity(0.75)
        static let sand = Color(red: 0.98, green: 0.86, blue: 0.62)
        static let sandDark = Color(red: 0.90, green: 0.74, blue: 0.50)
        static let grass = Color(red: 0.52, green: 0.78, blue: 0.40)
        static let grassDark = Color(red: 0.36, green: 0.62, blue: 0.30)
        static let leaf = Color(red: 0.30, green: 0.60, blue: 0.32)
        static let leafDark = Color(red: 0.18, green: 0.44, blue: 0.24)
        static let water = Color(red: 0.55, green: 0.80, blue: 0.94)
        static let petal = Color(red: 0.98, green: 0.62, blue: 0.72)
        // Light & shade
        static let shadow = Color.black.opacity(0.18)
        static let deepShadow = Color.black.opacity(0.35)
        static let highlight = Color.white.opacity(0.35)
        static let glass = Color(red: 0.80, green: 0.92, blue: 1.0).opacity(0.85)
        static let lampGlow = Color(red: 1.0, green: 0.90, blue: 0.55).opacity(0.35)
        static let cobweb = Color.white.opacity(0.35)
    }

    // MARK: Gradients
    static let background = LinearGradient(
        colors: [Color(red: 1.0, green: 0.93, blue: 0.94), Color(red: 0.96, green: 0.91, blue: 1.0)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let brand = LinearGradient(
        colors: [rose, plum],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Metrics
    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }
}
