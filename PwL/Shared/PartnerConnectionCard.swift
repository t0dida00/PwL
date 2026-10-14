import SwiftUI

/// Create / join a room with your matched love's device. Reusable by any two-player game.
/// Rooms are per game: only someone in the same game's lobby can join.
struct PartnerConnectionCard: View {
    @Environment(NearbyService.self) private var nearby
    @Environment(AccountStore.self) private var account

    /// The game whose lobby this is (e.g. `CaroGame.gameID`).
    let gameID: String

    private var localName: String { account.nickname }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            switch nearby.status {
            case .idle:
                idle
            case .hosting:
                waiting(title: "Room open", detail: "Ask \(account.loveNickname) to tap Join on their phone.")
            case .browsing:
                browsing
            case .connecting(let name):
                waiting(title: "Connecting to \(name)…", detail: "Hang on a second.")
            case .connected:
                connected
            case .lost:
                lost
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: nearby.status)
        .animation(.easeInOut(duration: 0.25), value: nearby.hosts)
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let notice = nearby.notice {
                Label(notice, systemImage: "door.left.hand.open")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.rose)
            }
            Text("Both of you open this game on your own phone, close together with Wi-Fi or Bluetooth on.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
            HStack(spacing: Theme.Spacing.s) {
                Button {
                    if let me = account.account, let loveUID = me.partnerUID {
                        nearby.host(as: localName, uid: me.uid, loveUID: loveUID, game: gameID)
                    }
                } label: {
                    Label("Create room", systemImage: "house.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    if let me = account.account, let loveUID = me.partnerUID {
                        nearby.browse(as: localName, uid: me.uid, loveUID: loveUID, game: gameID)
                    }
                } label: {
                    Label("Join", systemImage: "person.2.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var browsing: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                ProgressView()
                Text("Looking for \(account.loveNickname)'s room…")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            ForEach(nearby.hosts) { host in
                Button {
                    nearby.join(host)
                } label: {
                    HStack {
                        Image(systemName: "heart.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.rose)
                        Text(host.name)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("Join")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Theme.brand, in: Capsule())
                    }
                    .padding(Theme.Spacing.s)
                    .background(Theme.plum.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            cancelButton
        }
    }

    private func waiting(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                ProgressView()
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            Text(detail)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
            cancelButton
        }
    }

    private var connected: some View {
        HStack(spacing: Theme.Spacing.s) {
            playerBadge(localName, color: Theme.playerColor(nearby.isHost ? 0 : 1))
            Image(systemName: "heart.fill")
                .foregroundStyle(Theme.rose)
            playerBadge(nearby.partnerName ?? account.loveNickname, color: Theme.playerColor(nearby.isHost ? 1 : 0))
            Spacer(minLength: 0)
            Button("Leave", role: .destructive) { nearby.leaveLobby() }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.danger)
        }
    }

    private var lost: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("Connection lost", systemImage: "wifi.exclamationmark")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.danger)
            Button("Reconnect") { nearby.stop() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var cancelButton: some View {
        Button("Cancel") { nearby.stop() }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(Theme.plum)
    }

    private func playerBadge(_ name: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(name)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
    }
}
