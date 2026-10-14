import SwiftUI

/// A worksheet of scattered numbers with a magnifying glass on the one being found.
struct FindNumbersArtwork: View {
    /// (text, x, y, size, rotation) in unit coordinates of the square.
    private let numbers: [(String, CGFloat, CGFloat, CGFloat, Double)] = [
        ("12", 0.24, 0.22, 0.20, -18),
        ("3", 0.72, 0.18, 0.18, 14),
        ("25", 0.20, 0.72, 0.17, 12),
        ("41", 0.86, 0.52, 0.14, -22),
        ("8", 0.50, 0.88, 0.13, 8),
    ]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(numbers.indices, id: \.self) { i in
                    let n = numbers[i]
                    Text(n.0)
                        .font(.system(size: side * n.3, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .rotationEffect(.degrees(n.4))
                        .position(x: side * n.1, y: side * n.2)
                }
                // Magnifying glass over the target "7".
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: side * 0.40, height: side * 0.40)
                    Text("7")
                        .font(.system(size: side * 0.26, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.rose)
                    Circle()
                        .stroke(.white, lineWidth: side * 0.05)
                        .frame(width: side * 0.46, height: side * 0.46)
                    Capsule()
                        .fill(.white)
                        .frame(width: side * 0.07, height: side * 0.2)
                        .offset(y: side * 0.31)
                        .rotationEffect(.degrees(-45))
                }
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                .position(x: side * 0.5, y: side * 0.46)
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }
}
