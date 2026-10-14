import SwiftUI

/// Filled, full-width call-to-action button.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.brand, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .shadow(color: Theme.rose.opacity(0.35), radius: 10, y: 5)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Outlined secondary button.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(Theme.plum)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.plum.opacity(0.25), lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Round icon button used in game control bars.
struct CircleIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var tint: Color = Theme.plum
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Theme.surface, in: Circle())
                .shadow(color: Theme.plum.opacity(0.12), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Soft white card container.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.m)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .shadow(color: Theme.plum.opacity(0.1), radius: 12, y: 6)
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

/// Selectable pill chip.
struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(isSelected ? .white : Theme.plum)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.brand)
                    } else {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.plum.opacity(0.08))
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: isSelected)
    }
}

/// Shared in-game control bar. EVERY game must use it so the
/// menu / ? / music / pause controls stay consistent.
struct GameControlBar<Center: View>: View {
    let isMusicOn: Bool
    let isPaused: Bool
    let onMenu: () -> Void
    let onHelp: () -> Void
    let onToggleMusic: () -> Void
    let onPause: () -> Void
    @ViewBuilder let center: () -> Center

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            CircleIconButton(systemName: "line.3.horizontal", accessibilityLabel: "Menu", action: onMenu)
            Spacer(minLength: 0)
            center()
            Spacer(minLength: 0)
            CircleIconButton(systemName: "questionmark", accessibilityLabel: "How to play", action: onHelp)
            CircleIconButton(
                systemName: isMusicOn ? "music.note" : "speaker.slash.fill",
                accessibilityLabel: isMusicOn ? "Turn music off" : "Turn music on",
                tint: isMusicOn ? Theme.rose : Theme.inkSoft,
                action: onToggleMusic
            )
            CircleIconButton(
                systemName: isPaused ? "play.fill" : "pause.fill",
                accessibilityLabel: isPaused ? "Resume" : "Pause",
                action: onPause
            )
        }
    }
}

/// Dimmed full-screen backdrop + centered card, for pause/menu/result overlays.
struct ModalCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            // Scrolls only when the card is taller than the screen (e.g. in landscape).
            ViewThatFits(in: .vertical) {
                card
                ScrollView { card }
                    .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var card: some View {
        VStack(spacing: Theme.Spacing.m, content: content)
            .padding(Theme.Spacing.l)
            .frame(maxWidth: 340)
            .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .shadow(color: Theme.plum.opacity(0.2), radius: 24, y: 10)
            .padding(Theme.Spacing.l)
    }
}

enum TimeFormat {
    /// 75.43 → "01:15.4"
    static func clock(_ interval: TimeInterval) -> String {
        let tenths = Int((max(0, interval) * 10).rounded(.down))
        return String(format: "%02d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }
}
