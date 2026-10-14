import SwiftUI

struct LoginView: View {
    @Environment(AccountStore.self) private var account
    @State private var code = ""
    @State private var usingCode = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.l) {
                Spacer()
                VStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 88))
                        .foregroundStyle(Theme.brand)
                        .shadow(color: Theme.rose.opacity(0.35), radius: 16, y: 8)
                    Text("Welcome to PwL")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .foregroundStyle(Theme.ink)
                    Text("Play with Lovers — little games for two")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()

                VStack(spacing: Theme.Spacing.m) {
                    Button {
                        usingCode = false
                        Task { await account.signIn() }
                    } label: {
                        HStack(spacing: Theme.Spacing.s) {
                            if account.isWorking && !usingCode {
                                ProgressView().tint(Theme.ink)
                            } else {
                                GoogleMark()
                            }
                            Text(account.backend.isRemote ? "Continue with Google" : "Continue with test account")
                        }
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                                .stroke(Theme.ink.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: Theme.plum.opacity(0.12), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(account.isWorking)

                    codeSignIn

                    if let error = account.errorMessage {
                        Text(error)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                    }

                    if account.backend.isRemote {
                        Text("Your first sign-in is with Google and gives you your own 8-character PwL ID. After that you can sign in with just the ID. Share it with your love to match.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                    } else {
                        Label("Google sign-in isn't set up yet (missing GoogleService-Info.plist). This test account stays on this device.", systemImage: "wrench.and.screwdriver.fill")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
    }
}

private extension LoginView {
    var codeSignIn: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Rectangle().fill(Theme.ink.opacity(0.12)).frame(height: 1)
                Text("or")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Rectangle().fill(Theme.ink.opacity(0.12)).frame(height: 1)
            }
            TextField("Your PwL ID", text: $code)
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($codeFocused)
                .submitLabel(.go)
                .onSubmit(signInWithCode)
                .padding(14)
                .background(Theme.plum.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .onChange(of: code) { _, value in
                    let normalized = String(AccountCode.normalize(value).prefix(AccountCode.length))
                    if normalized != value { code = normalized }
                }
            Button(action: signInWithCode) {
                if account.isWorking && usingCode {
                    ProgressView().tint(Theme.plum)
                } else {
                    Label("Sign in with PwL ID", systemImage: "number")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(code.count != AccountCode.length || account.isWorking)
        }
    }

    func signInWithCode() {
        guard code.count == AccountCode.length, !account.isWorking else { return }
        codeFocused = false
        usingCode = true
        Task { await account.signIn(withCode: code) }
    }
}

/// Simple four-color "G" so we don't ship Google's logo asset.
private struct GoogleMark: View {
    var body: some View {
        Text("G")
            .font(.system(size: 20, weight: .black, design: .rounded))
            .foregroundStyle(
                AngularGradient(
                    colors: [.red, .yellow, .green, .blue, .red],
                    center: .center
                )
            )
            .frame(width: 24, height: 24)
    }
}

#Preview {
    LoginView().environment(AccountStore(backend: LocalAccountBackend()))
}
