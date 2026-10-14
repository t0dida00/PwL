import CoreGraphics
import Foundation

struct FindNumbersConfig: Hashable, Codable {
    /// Which number the player must find next.
    enum Order: String, CaseIterable, Codable {
        case ascending   // 1 → N
        case descending  // N → 1
        case random      // the game picks the next number

        var title: String {
            switch self {
            case .ascending: "1 → N"
            case .descending: "N → 1"
            case .random: "Random"
            }
        }
    }

    /// How big the numbers are drawn on the board.
    enum SizeStyle: String, CaseIterable, Codable {
        case mixed
        case small
        case big

        var title: String {
            switch self {
            case .mixed: "Mixed"
            case .small: "Small"
            case .big: "Big"
            }
        }

        /// Range of the per-number scale factor (1 = fills its cell).
        var scaleRange: ClosedRange<Double> {
            switch self {
            case .mixed: 0.45...1.0
            case .small: 0.42...0.55
            case .big: 0.85...1.0
            }
        }
    }

    static let presets = [50, 100, 150, 200]
    static let allowedRange = 5...500

    var count: Int
    var order: Order = .ascending
    var sizeStyle: SizeStyle = .mixed

    /// The full order in which numbers must be found.
    func makeSequence(using rng: inout some RandomNumberGenerator) -> [Int] {
        switch order {
        case .ascending: Array(1...count)
        case .descending: Array((1...count).reversed())
        case .random: Array(1...count).shuffled(using: &rng)
        }
    }
}

/// One number placed on the board. Layout values are cell-relative so the
/// board can be drawn at any zoom level.
struct NumberTile: Identifiable, Hashable {
    let value: Int
    let column: Int
    let row: Int
    /// Offset from the cell center as a fraction of the cell size.
    let offsetX: Double
    let offsetY: Double
    /// 0…1 multiplier on the base font size.
    let scale: Double
    let rotation: Double
    let colorIndex: Int

    var id: Int { value }

    /// 6 and 9 look alike when tilted, so these get an underline.
    var needsUnderline: Bool {
        let digits = String(value)
        return digits.contains("6") || digits.contains("9")
    }
}

struct FindNumbersBoard: Hashable {
    let columns: Int
    let rows: Int
    let tiles: [NumberTile]
}

enum FindNumbersBoardGenerator {
    /// Width / height of the area the board is meant to fill (portrait phone).
    static let aspect = 0.66

    static func make(
        config: FindNumbersConfig,
        paletteCount: Int,
        using rng: inout some RandomNumberGenerator
    ) -> FindNumbersBoard {
        let count = max(1, config.count)
        let columns = max(2, Int((Double(count) * aspect).squareRoot().rounded(.up)))
        let rows = Int((Double(count) / Double(columns)).rounded(.up))

        // Pick random cells for the numbers, then shuffle which number goes where.
        let cells = Array(0..<(columns * rows)).shuffled(using: &rng).prefix(count)
        let values = Array(1...count).shuffled(using: &rng)

        let tiles = zip(cells, values).map { cell, value in
            let scale = Double.random(in: config.sizeStyle.scaleRange, using: &rng)
            // Smaller numbers can wander further from the cell center without overlapping.
            let wander = max(0.04, (1 - scale) * 0.4)
            return NumberTile(
                value: value,
                column: cell % columns,
                row: cell / columns,
                offsetX: Double.random(in: -wander...wander, using: &rng),
                offsetY: Double.random(in: -wander...wander, using: &rng),
                scale: scale,
                rotation: Double.random(in: -40...40, using: &rng),
                colorIndex: Int.random(in: 0..<max(1, paletteCount), using: &rng)
            )
        }
        return FindNumbersBoard(columns: columns, rows: rows, tiles: tiles)
    }
}
