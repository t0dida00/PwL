import SwiftUI

struct FindNumbersSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(AccountStore.self) private var account
    @Environment(NearbyService.self) private var nearby

    @AppStorage("findNumbers.lastCount") private var presetCount = 50
    @AppStorage("findNumbers.useCustom") private var useCustom = false
    @AppStorage("findNumbers.customCount") private var customCount = 300
    @AppStorage("findNumbers.order") private var order: FindNumbersConfig.Order = .ascending
    @AppStorage("findNumbers.size") private var sizeStyle: FindNumbersConfig.SizeStyle = .mixed
    @FocusState private var customFocused: Bool

    private var range: ClosedRange<Int> { FindNumbersConfig.allowedRange }
    private var count: Int { useCustom ? customCount : presetCount }
    private var isValid: Bool { range.contains(count) }
    private var config: FindNumbersConfig { FindNumbersConfig(count: count, order: order, sizeStyle: sizeStyle) }
    private var localName: String { account.nickname }
    /// A connected guest waits while the host picks settings.
    private var isWaitingGuest: Bool { nearby.isConnected && !nearby.isHost }
    private var canStart: Bool { isValid && nearby.isConnected && nearby.isHost }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                header

                section("Your love") {
                    if account.isPaired {
                        PartnerConnectionCard()
                    } else {
                        notMatched
                    }
                }

                if isWaitingGuest {
                    waitingForHost
                } else {
                    settings
                }
            }
            .padding(Theme.Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Find Numbers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { customFocused = false }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isWaitingGuest)
        .onAppear { nearby.onGameMessage = handleMessage }
    }

    @ViewBuilder
    private var settings: some View {
        section("How many numbers?") {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(FindNumbersConfig.presets, id: \.self) { preset in
                    ChipButton(title: "\(preset)", isSelected: !useCustom && presetCount == preset) {
                        presetCount = preset
                        useCustom = false
                        customFocused = false
                    }
                }
            }
            customRow
        }

        section("Count") {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(FindNumbersConfig.Order.allCases, id: \.self) { option in
                    ChipButton(title: option.title, isSelected: order == option) { order = option }
                }
            }
            Text(orderDescription)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
        }

        section("Number size") {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(FindNumbersConfig.SizeStyle.allCases, id: \.self) { option in
                    ChipButton(title: option.title, isSelected: sizeStyle == option) { sizeStyle = option }
                }
            }
        }

        Button("Start match", action: start)
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canStart)
            .padding(.top, Theme.Spacing.s)
        if !nearby.isConnected {
            Text("Connect with \(account.loveNickname) to start")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var notMatched: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Match with your love first — enter their PwL ID in Settings.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
            Button("Go to Settings") { appState.selectedTab = .settings }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var waitingForHost: some View {
        VStack(spacing: Theme.Spacing.s) {
            ProgressView()
            Text("Waiting for \(nearby.partnerName ?? account.loveNickname) to pick the settings and start…")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func start() {
        customFocused = false
        var partner = nearby.partnerName ?? account.loveNickname
        if partner.lowercased() == localName.lowercased() { partner += " 2" }
        let match = FindNumbersMatch(
            config: config,
            seed: .random(in: .min ... .max),
            playerNames: [localName, partner],
            localPlayer: 0
        )
        nearby.send(FindNumbersMessage.start(match))
        appState.path.append(.findNumbersMatch(match))
    }

    /// Guest side: the host started a match.
    private func handleMessage(_ data: Data) {
        guard case .start(var match) = try? JSONDecoder().decode(FindNumbersMessage.self, from: data) else { return }
        match.localPlayer = 1
        appState.path.append(.findNumbersMatch(match))
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.xs) {
            RoundedRectangle(cornerRadius: Theme.Radius.medium + 4, style: .continuous)
                .fill(LinearGradient(colors: [Theme.rose, Theme.peach], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 88, height: 88)
                .overlay { FindNumbersArtwork() }
                .shadow(color: Theme.rose.opacity(0.25), radius: 10, y: 5)
            Text("Race your love — whoever spots the number first scores!")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, Theme.Spacing.s)
    }

    private var orderDescription: String {
        switch order {
        case .ascending: "Find 1, 2, 3… up to \(count)"
        case .descending: "Find \(count), \(count - 1), \(count - 2)… down to 1"
        case .random: "The game picks the next number for you — every number, no pattern"
        }
    }

    private var customRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("Custom")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(useCustom ? Theme.rose : Theme.ink)
            Spacer()
            TextField("1–500", value: $customCount, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(.headline, design: .rounded))
                .frame(width: 70)
                .padding(.vertical, 8)
                .background(Theme.plum.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                .focused($customFocused)
            Stepper("Custom amount", value: $customCount, in: range, step: 10)
                .labelsHidden()
        }
        .padding(Theme.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .stroke(useCustom ? Theme.rose : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture { useCustom = true }
        .onChange(of: customFocused) { _, focused in if focused { useCustom = true } }
        .onChange(of: customCount) { useCustom = true }
        .overlay(alignment: .bottomLeading) {
            if useCustom && !isValid {
                Text("Pick \(range.lowerBound)–\(range.upperBound)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.danger)
                    .offset(x: Theme.Spacing.s, y: 18)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.plum)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
