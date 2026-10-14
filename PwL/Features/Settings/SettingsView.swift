import PhotosUI
import SwiftUI
import UIKit

/// Avatar, nickname, your PwL ID, matching with your love, sign out.
struct SettingsView: View {
    @Environment(AccountStore.self) private var account

    @State private var nickname = ""
    @State private var loveCode = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var copied = false
    @State private var confirmUnpair = false
    @State private var confirmSignOut = false
    @FocusState private var focusedField: Field?

    private enum Field { case nickname, loveCode }

    private var me: UserAccount? { account.account }
    private var nicknameChanged: Bool {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != me?.nickname
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                profileCard
                idCard
                loveCard
                if let error = account.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                accountCard
            }
            .padding(Theme.Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nickname = me?.nickname ?? ""
            account.errorMessage = nil
        }
        .onChange(of: me?.nickname) { _, newValue in
            if focusedField != .nickname { nickname = newValue ?? "" }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let avatar = AvatarImage.prepare(data) {
                    await account.updateAvatar(avatar)
                }
                photoItem = nil
            }
        }
        .alert("Unpair from \(account.loveNickname)?", isPresented: $confirmUnpair) {
            Button("Cancel", role: .cancel) {}
            Button("Unpair", role: .destructive) { Task { await account.unpair() } }
        } message: {
            Text("You'll both be free to match again. If you match each other later, your stats come back.")
        }
        .alert("Sign out?", isPresented: $confirmSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) { Task { await account.signOut() } }
        } message: {
            Text("You can sign back in anytime. Your PwL ID and match stay saved.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    // MARK: Cards

    private var profileCard: some View {
        VStack(spacing: Theme.Spacing.m) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                AvatarView(data: me?.avatar, name: me?.nickname ?? "?", size: 104, color: Theme.playerColor(0))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Theme.brand, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change avatar")

            if me?.avatar != nil {
                Button("Remove photo", role: .destructive) { Task { await account.updateAvatar(nil) } }
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                sectionTitle("Nickname")
                HStack(spacing: Theme.Spacing.s) {
                    TextField("Your nickname", text: $nickname)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .nickname)
                        .submitLabel(.done)
                        .onSubmit(saveNickname)
                        .padding(12)
                        .background(Theme.plum.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    Button("Save", action: saveNickname)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Theme.brand, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                        .opacity(nicknameChanged ? 1 : 0.4)
                        .disabled(!nicknameChanged)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var idCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            sectionTitle("Your PwL ID")
            HStack {
                Text(AccountCode.formatted(me?.code ?? ""))
                    .font(.system(size: 30, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.rose)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    UIPasteboard.general.string = me?.code
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.plum)
                        .frame(width: 40, height: 40)
                        .background(Theme.plum.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Copy ID")
                if let code = me?.code {
                    ShareLink(item: "Match with me on PwL 💕 My PwL ID is \(code)") {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.plum)
                            .frame(width: 40, height: 40)
                            .background(Theme.plum.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Share ID")
                }
            }
            Text("Your love enters this ID to match with you.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var loveCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            sectionTitle("Your love")
            if account.isPaired {
                HStack(spacing: Theme.Spacing.m) {
                    AvatarView(data: account.love?.avatar, name: account.loveNickname, size: 60, color: Theme.playerColor(1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.loveNickname)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        if let code = account.love?.code {
                            Text(AccountCode.formatted(code))
                                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        TimelineView(.periodic(from: .now, by: 10)) { context in
                            let online = account.love?.isOnline(at: context.date) == true
                            Label(LastSeenFormat.presence(account.love, now: context.date), systemImage: "circle.fill")
                                .labelStyle(PresenceLabelStyle(online: online))
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(online ? Theme.success : Theme.inkSoft)
                        }
                    }
                    Spacer()
                    Image(systemName: "heart.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.rose)
                }
                Button("Unpair", role: .destructive) { confirmUnpair = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(account.isWorking)
            } else {
                ForEach(account.incomingRequests) { request in
                    incomingRequestRow(request)
                }
                if let outgoing = account.outgoingRequest {
                    outgoingRequestRow(outgoing)
                } else {
                    TextField("Enter your love's PwL ID", text: $loveCode)
                        // Rounded placeholder fits on one line; the typed ID stays monospaced.
                        .font(loveCode.isEmpty
                              ? .system(.callout, design: .rounded, weight: .medium)
                              : .system(.headline, design: .monospaced, weight: .bold))
                        .lineLimit(1)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .loveCode)
                        .submitLabel(.go)
                        .onSubmit(match)
                        .padding(14)
                        .background(Theme.plum.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                        .onChange(of: loveCode) { _, value in
                            let normalized = String(AccountCode.normalize(value).prefix(AccountCode.length))
                            if normalized != value { loveCode = normalized }
                        }
                    Button(action: match) {
                        if account.isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Label("Send request", systemImage: "heart.fill")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(loveCode.count != AccountCode.length || account.isWorking)
                }
            }
            Label("Your love gets a request to accept. You can match with one love at a time.", systemImage: "info.circle")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            sectionTitle("Account")
            if let email = me?.email, !email.isEmpty {
                Label(email, systemImage: "envelope.fill")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            Button("Sign out", role: .destructive) { confirmSignOut = true }
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.danger)
                .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(Theme.plum)
            .textCase(.uppercase)
    }

    // MARK: Actions

    private func saveNickname() {
        guard nicknameChanged else { return }
        focusedField = nil
        Task { await account.updateNickname(nickname) }
    }

    private func match() {
        focusedField = nil
        Task {
            if await account.requestMatch(withCode: loveCode) { loveCode = "" }
        }
    }

    private func incomingRequestRow(_ request: LoveRequest) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                AvatarView(data: nil, name: request.fromNickname, size: 44, color: Theme.playerColor(1))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(request.fromNickname) wants to be your love")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(AccountCode.formatted(request.fromCode))
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: Theme.Spacing.s) {
                Button("Decline") { Task { await account.decline(request) } }
                    .buttonStyle(SecondaryButtonStyle())
                Button {
                    Task { await account.accept(request) }
                } label: {
                    Label("Accept", systemImage: "heart.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .disabled(account.isWorking)
        }
        .padding(Theme.Spacing.s + 4)
        .background(Theme.rose.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private func outgoingRequestRow(_ request: LoveRequest) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "paperplane.fill")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Theme.rose)
                    .frame(width: 44, height: 44)
                    .background(Theme.rose.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Waiting for \(request.toNickname) to accept")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(AccountCode.formatted(request.toCode))
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
                ProgressView().tint(Theme.rose)
            }
            Button("Cancel request") { Task { await account.cancelOutgoingRequest() } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(account.isWorking)
        }
    }
}

/// Small status dot before the presence text.
private struct PresenceLabelStyle: LabelStyle {
    let online: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .font(.system(size: 7))
                .opacity(online ? 1 : 0.5)
            configuration.title
        }
    }
}
