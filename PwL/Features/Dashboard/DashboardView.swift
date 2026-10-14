import SwiftUI

/// Couple metrics: days played together, games, minutes, last online.
struct DashboardView: View {
    @Environment(AccountStore.self) private var account
    @Environment(AppState.self) private var appState

    private let columns = [GridItem(.flexible(), spacing: Theme.Spacing.m), GridItem(.flexible(), spacing: Theme.Spacing.m)]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                coupleHeader

                if account.isPaired {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
                        MetricTile(
                            icon: "calendar.badge.checkmark",
                            value: "\(stats.daysPlayed)",
                            title: stats.daysPlayed == 1 ? "Day played together" : "Days played together",
                            color: Theme.rose
                        )
                        MetricTile(
                            icon: "gamecontroller.fill",
                            value: "\(stats.gamesPlayed)",
                            title: stats.gamesPlayed == 1 ? "Game played" : "Games played",
                            color: Theme.plum
                        )
                        MetricTile(
                            icon: "clock.fill",
                            value: "\(stats.minutesPlayed)",
                            title: "Minutes played",
                            color: Theme.peach
                        )
                        // Re-evaluated every 10s so a stale heartbeat flips to offline quickly.
                        TimelineView(.periodic(from: .now, by: 10)) { context in
                            let online = account.love?.isOnline(at: context.date) == true
                            MetricTile(
                                icon: online ? "dot.radiowaves.left.and.right" : "moon.zzz.fill",
                                value: online ? "Online" : "Offline",
                                title: online
                                    ? "\(account.loveNickname) is in the app"
                                    : "\(account.loveNickname) · \(LastSeenFormat.presence(account.love, now: context.date).lowercased())",
                                color: online ? Theme.success : Theme.inkSoft
                            )
                        }
                    }

                    if let lastPlayed = stats.lastPlayedAt {
                        Label("Last game together \(LastSeenFormat.text(lastPlayed).lowercased())", systemImage: "sparkles")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.plum)
                    }
                } else {
                    notPairedCard
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var stats: CoupleStats { account.stats ?? CoupleStats() }

    private var coupleHeader: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: -14) {
                AvatarView(data: account.account?.avatar, name: account.nickname, size: 76, color: Theme.playerColor(0))
                    .zIndex(1)
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.brand, in: Circle())
                    .zIndex(2)
                Group {
                    if account.isPaired {
                        AvatarView(data: account.love?.avatar, name: account.loveNickname, size: 76, color: Theme.playerColor(1))
                    } else {
                        Image(systemName: "questionmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.inkSoft)
                            .frame(width: 76, height: 76)
                            .background(Theme.plum.opacity(0.08), in: Circle())
                            .overlay(Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5])).foregroundStyle(Theme.plum.opacity(0.3)))
                    }
                }
            }
            Text(account.isPaired ? "\(account.nickname) & \(account.loveNickname)" : account.nickname)
                .font(.system(.title2, design: .rounded, weight: .black))
                .foregroundStyle(Theme.ink)
            if account.isPaired, let pairedAt = stats.pairedAt {
                Text("Matched since \(pairedAt.formatted(date: .abbreviated, time: .omitted)) · \(daysSince(pairedAt)) days")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var notPairedCard: some View {
        VStack(spacing: Theme.Spacing.m) {
            Text("You're not matched yet")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Share your PwL ID with your love, or enter theirs in Settings.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            if let code = account.account?.code {
                Text(AccountCode.formatted(code))
                    .font(.system(size: 30, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.rose)
                    .textSelection(.enabled)
            }
            if let request = account.incomingRequests.first {
                Button("See \(request.fromNickname)'s request") { appState.selectedTab = .settings }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Match with my love") { appState.selectedTab = .settings }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func daysSince(_ date: Date) -> Int {
        max(1, (Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0) + 1)
    }
}

private struct MetricTile: View {
    let icon: String
    let value: String
    let title: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            Text(value)
                .font(.system(.title, design: .rounded, weight: .black).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
