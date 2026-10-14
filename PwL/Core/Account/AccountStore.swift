import Foundation
import Observation

/// Signed-in user, their love and their shared stats — kept live via backend listeners.
@MainActor
@Observable
final class AccountStore {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn
    }

    private(set) var state: State = .loading
    private(set) var account: UserAccount?
    private(set) var love: UserAccount?
    private(set) var stats: CoupleStats?
    /// People asking to be your love, oldest first.
    private(set) var incomingRequests: [LoveRequest] = []
    /// Your pending request (one at a time).
    private(set) var outgoingRequest: LoveRequest?
    private(set) var isWorking = false
    var errorMessage: String?

    let backend: AccountBackend
    @ObservationIgnored private var accountListener: ListenerToken?
    @ObservationIgnored private var loveListener: ListenerToken?
    @ObservationIgnored private var statsListener: ListenerToken?
    @ObservationIgnored private var incomingListener: ListenerToken?
    @ObservationIgnored private var outgoingListener: ListenerToken?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    /// Whether we last told the backend we're online (avoids duplicate offline writes).
    @ObservationIgnored private var markedOnline = false

    init(backend: AccountBackend) {
        self.backend = backend
    }

    var isPaired: Bool { account?.isPaired == true }
    var nickname: String { account?.nickname ?? "Me" }
    var loveNickname: String { love?.nickname ?? "Love" }
    /// [me, my love] — used for match names and the scoreboard.
    var playerNames: [String] { [nickname, loveNickname] }

    // MARK: Session

    func restore() async {
        guard let uid = backend.currentUID else {
            state = .signedOut
            return
        }
        await finishSignIn(uid: uid)
    }

    func signIn() async {
        await perform {
            let uid = try await backend.signIn()
            await finishSignIn(uid: uid)
        }
    }

    func signIn(withCode input: String) async {
        let code = AccountCode.normalize(input)
        guard AccountCode.isValid(code) else {
            errorMessage = AccountError.invalidCode.errorDescription
            return
        }
        await perform {
            let uid = try await backend.signIn(code: code)
            await finishSignIn(uid: uid)
        }
    }

    func signOut() async {
        stopHeartbeat()
        markedOnline = false
        if let uid = account?.uid { await backend.setOnline(uid: uid, false) }
        do {
            try backend.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        stopListening()
        account = nil
        love = nil
        stats = nil
        incomingRequests = []
        outgoingRequest = nil
        state = .signedOut
    }

    /// The app is on screen: show as online and keep the heartbeat going.
    func appBecameActive() {
        guard let uid = account?.uid else { return }
        startHeartbeat(uid: uid)
    }

    /// The app left the screen: show as offline straight away. Called on `.inactive`
    /// too, because swiping the app away in the app switcher kills it before
    /// `.background` arrives.
    func appWentToBackground() async {
        stopHeartbeat()
        guard markedOnline, let uid = account?.uid else { return }
        markedOnline = false
        await backend.setOnline(uid: uid, false)
    }

    // MARK: Profile & matching

    @discardableResult
    func updateNickname(_ nickname: String) async -> Bool {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid = account?.uid, !trimmed.isEmpty else { return false }
        return await perform { try await backend.updateNickname(uid: uid, nickname: String(trimmed.prefix(24))) }
    }

    @discardableResult
    func updateAvatar(_ data: Data?) async -> Bool {
        guard let uid = account?.uid else { return false }
        return await perform { try await backend.updateAvatar(uid: uid, avatar: data) }
    }

    /// Sends a match request to the owner of the PwL ID. Returns `true` once it's sent
    /// (or, if they had already asked you, once you're matched).
    @discardableResult
    func requestMatch(withCode input: String) async -> Bool {
        let code = AccountCode.normalize(input)
        guard let account else { return false }
        guard AccountCode.isValid(code) else {
            errorMessage = AccountError.invalidCode.errorDescription
            return false
        }
        guard code != account.code else {
            errorMessage = AccountError.cannotPairWithSelf.errorDescription
            return false
        }
        guard !account.isPaired else {
            errorMessage = AccountError.alreadyPaired.errorDescription
            return false
        }
        return await perform { _ = try await backend.sendRequest(from: account, toCode: code) }
    }

    @discardableResult
    func accept(_ request: LoveRequest) async -> Bool {
        await perform { try await backend.acceptRequest(request) }
    }

    @discardableResult
    func decline(_ request: LoveRequest) async -> Bool {
        await perform { try await backend.deleteRequest(request) }
    }

    @discardableResult
    func cancelOutgoingRequest() async -> Bool {
        guard let outgoingRequest else { return false }
        return await perform { try await backend.deleteRequest(outgoingRequest) }
    }

    @discardableResult
    func unpair() async -> Bool {
        guard let uid = account?.uid else { return false }
        return await perform { try await backend.unpair(uid: uid) }
    }

    /// Called by the match host when a game finishes.
    func recordGame(seconds: Double, at date: Date = .now) async {
        guard let pairID = account?.pairID else { return }
        try? await backend.recordGame(pairID: pairID, seconds: seconds, day: CoupleStats.dayKey(for: date))
    }

    // MARK: Private

    private func finishSignIn(uid: String) async {
        do {
            let loaded = try await backend.loadOrCreateAccount(uid: uid)
            account = loaded
            listen(uid: uid)
            state = .signedIn
            startHeartbeat(uid: uid)
            await backend.enableCodeSignIn(code: loaded.code)
        } catch {
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }

    /// Runs a backend call, surfacing errors in `errorMessage`. Returns success.
    @discardableResult
    private func perform(_ work: () async throws -> Void) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await work()
            return true
        } catch AccountError.cancelled {
            return false
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    private func listen(uid: String) {
        stopListening()
        accountListener = backend.observeAccount(uid: uid) { [weak self] account in
            self?.accountChanged(account)
        }
        incomingListener = backend.observeRequests(uid: uid, incoming: true) { [weak self] requests in
            self?.incomingRequests = requests
            self?.clearRequestsIfPaired()
        }
        outgoingListener = backend.observeRequests(uid: uid, incoming: false) { [weak self] requests in
            self?.outgoingRequest = requests.last
            self?.clearRequestsIfPaired()
        }
    }

    private func startHeartbeat(uid: String) {
        heartbeat?.cancel()
        markedOnline = true
        heartbeat = Task { [backend] in
            while !Task.isCancelled {
                await backend.setOnline(uid: uid, true)
                try? await Task.sleep(for: .seconds(UserAccount.heartbeat))
            }
        }
    }

    private func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    /// Once matched, leftover requests to or from you no longer mean anything.
    private func clearRequestsIfPaired() {
        guard isPaired else { return }
        let stale = incomingRequests + [outgoingRequest].compactMap { $0 }
        guard !stale.isEmpty else { return }
        Task {
            for request in stale { try? await backend.deleteRequest(request) }
        }
    }

    private func accountChanged(_ newAccount: UserAccount?) {
        let old = account
        guard let newAccount else { return }
        account = newAccount
        if newAccount.isPaired, old?.isPaired != true { clearRequestsIfPaired() }

        if newAccount.partnerUID != old?.partnerUID || loveListener == nil {
            loveListener?.cancel()
            loveListener = nil
            love = nil
            if let loveUID = newAccount.partnerUID {
                loveListener = backend.observeAccount(uid: loveUID) { [weak self] love in
                    self?.love = love
                }
            }
        }
        if newAccount.pairID != old?.pairID || statsListener == nil {
            statsListener?.cancel()
            statsListener = nil
            stats = nil
            if let pairID = newAccount.pairID {
                statsListener = backend.observeStats(pairID: pairID) { [weak self] stats in
                    self?.stats = stats
                }
            }
        }
    }

    private func stopListening() {
        accountListener?.cancel()
        loveListener?.cancel()
        statsListener?.cancel()
        incomingListener?.cancel()
        outgoingListener?.cancel()
        incomingListener = nil
        outgoingListener = nil
        accountListener = nil
        loveListener = nil
        statsListener = nil
    }
}
