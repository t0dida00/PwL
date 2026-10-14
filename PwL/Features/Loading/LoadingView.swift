import SwiftUI

struct LoadingView: View {
    let onFinished: () -> Void

    @State private var progress: Double = 0
    @State private var beat = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.l) {
                Spacer()
                ZStack {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 120))
                        .foregroundStyle(Theme.brand)
                        .scaleEffect(beat ? 1.08 : 0.94)
                        .shadow(color: Theme.rose.opacity(0.4), radius: 20, y: 8)
                    Text("PwL")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: beat)

                VStack(spacing: Theme.Spacing.xs) {
                    Text("Play with Lovers")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("Little games for two")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.rose)
                    .frame(maxWidth: 220)
                    .padding(.bottom, 60)
            }
        }
        .onAppear { beat = true }
        .task {
            for step in 1...20 {
                try? await Task.sleep(for: .milliseconds(70))
                withAnimation(.linear(duration: 0.07)) { progress = Double(step) / 20 }
            }
            try? await Task.sleep(for: .milliseconds(150))
            onFinished()
        }
    }
}

#Preview {
    LoadingView {}
}
