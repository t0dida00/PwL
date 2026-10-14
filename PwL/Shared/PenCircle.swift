import SwiftUI

/// A hand-drawn-looking circle that "draws itself" when it appears.
struct PenCircle: View {
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
