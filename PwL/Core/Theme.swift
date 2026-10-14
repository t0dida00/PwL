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
