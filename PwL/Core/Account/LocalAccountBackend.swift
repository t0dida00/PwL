import Foundation

/// On-device stand-in for Firebase: used by unit tests and by debug builds before
/// `GoogleService-Info.plist` is added. "Sign in" creates a local test account, and
/// sending a request to any unknown PwL ID creates a pretend love who accepts it
/// shortly after, so every screen can be tried.
@MainActor
final class LocalAccountBackend: AccountBackend {
    private struct Storage: Codable {
        var currentUID: String?
        var accounts: [String: StoredAccount] = [:]
        var pairs: [String: StoredStats] = [:]
        var requests: [String: StoredRequest] = [:]
    }

    private struct StoredRequest: Codable {
        var from: String
        var to: String
        var createdAt: Date
    }

    private struct StoredAccount: Codable {
        var code: String
        var nickname: String
        var email: String
        var avatar: Data?
        var partnerUID: String?
        var pairID: String?
        var lastOnline: Date?
        var online: Bool?
    }

    private struct StoredStats: Codable {
        var pairedAt: Date?
        var gamesPlayed = 0
        var secondsPlayed: Double = 0
        var playDays: [String] = []
        var lastPlayedAt: Date?
    }

    private static let key = "pwl.localBackend"
    let isRemote = false
    private let defaults: UserDefaults
    private var storage: Storage
    private var accountObservers: [UUID: (uid: String, onChange: @MainActor @Sendable (UserAccount?) -> Void)] = [:]
    private var statsObservers: [UUID: (pairID: String, onChange: @MainActor @Sendable (CoupleStats?) -> Void)] = [:]
    private var requestObservers: [UUID: (uid: String, incoming: Bool, onChange: @MainActor @Sendable ([LoveRequest]) -> Void)] = [:]
    /// How long a pretend love takes to accept; `nil` = never (tests).
    private let pretendLoveReplyDelay: Duration?

    init(defaults: UserDefaults = .standard, pretendLoveReplyDelay: Duration? = .seconds(2)) {
        self.defaults = defaults
        self.pretendLoveReplyDelay = pretendLoveReplyDelay
        storage = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Storage.self, from: $0) } ?? Storage()
    }

    var currentUID: String? { storage.currentUID }

    func signIn() async throws -> String {
        let uid = "local-" + UUID().uuidString.prefix(8)
        storage.currentUID = uid
        save()
        return uid
    }

    func signIn(code: String) async throws -> String {
        guard let uid = storage.accounts.first(where: { $0.value.code == code })?.key else {
            throw AccountError.codeNotFound
        }
        storage.currentUID = uid
        save()
        return uid
    }

    func enableCodeSignIn(code: String) async {}

    func signOut() throws {
        storage.currentUID = nil
        save()
    }

    func loadOrCreateAccount(uid: String) async throws -> UserAccount {
        if storage.accounts[uid] == nil {
            storage.accounts[uid] = StoredAccount(code: uniqueCode(), nickname: "Lover", email: "test@pwl.local", lastOnline: .now)
            save()
        }
        return account(uid)!
    }

    func observeAccount(uid: String, onChange: @escaping @MainActor @Sendable (UserAccount?) -> Void) -> ListenerToken {
        let id = UUID()
        accountObservers[id] = (uid, onChange)
        onChange(account(uid))
        return LocalListener { [weak self] in self?.accountObservers[id] = nil }
    }

    func observeStats(pairID: String, onChange: @escaping @MainActor @Sendable (CoupleStats?) -> Void) -> ListenerToken {
        let id = UUID()
        statsObservers[id] = (pairID, onChange)
        onChange(stats(pairID))
        return LocalListener { [weak self] in self?.statsObservers[id] = nil }
    }

    func updateNickname(uid: String, nickname: String) async throws {
        storage.accounts[uid]?.nickname = nickname
        commit()
    }

    func updateAvatar(uid: String, avatar: Data?) async throws {
        storage.accounts[uid]?.avatar = avatar
        commit()
    }

    func observeRequests(uid: String, incoming: Bool, onChange: @escaping @MainActor @Sendable ([LoveRequest]) -> Void) -> ListenerToken {
        let id = UUID()
        requestObservers[id] = (uid, incoming, onChange)
        onChange(requests(uid: uid, incoming: incoming))
        return LocalListener { [weak self] in self?.requestObservers[id] = nil }
    }

    func sendRequest(from me: UserAccount, toCode code: String) async throws -> Bool {
        guard code != me.code else { throw AccountError.cannotPairWithSelf }
        guard storage.accounts[me.uid]?.partnerUID == nil else { throw AccountError.alreadyPaired }
        let loveUID = storage.accounts.first { $0.value.code == code }?.key ?? createPretendLove(code: code)
        guard storage.accounts[loveUID]?.partnerUID == nil else { throw AccountError.loveAlreadyPaired }

        if let theirs = request(LoveRequest.id(from: loveUID, to: me.uid)) {
            try await acceptRequest(theirs)
            return true
        }
        storage.requests = storage.requests.filter { $0.value.from != me.uid }
        let id = LoveRequest.id(from: me.uid, to: loveUID)
        storage.requests[id] = StoredRequest(from: me.uid, to: loveUID, createdAt: .now)
        commit()

        if loveUID.hasPrefix(Self.pretendPrefix), let delay = pretendLoveReplyDelay, let sent = request(id) {
            Task { [weak self] in
                try? await Task.sleep(for: delay)
                try? await self?.acceptRequest(sent)
            }
        }
        return false
    }

    func acceptRequest(_ request: LoveRequest) async throws {
        guard storage.requests[request.id] != nil else { throw AccountError.requestGone }
        guard storage.accounts[request.toUID]?.partnerUID == nil else { throw AccountError.alreadyPaired }
        guard storage.accounts[request.fromUID]?.partnerUID == nil else {
            storage.requests[request.id] = nil
            commit()
            throw AccountError.loveAlreadyPaired
        }
        let pairID = [request.fromUID, request.toUID].sorted().joined(separator: "_")
        storage.accounts[request.fromUID]?.partnerUID = request.toUID
        storage.accounts[request.fromUID]?.pairID = pairID
        storage.accounts[request.toUID]?.partnerUID = request.fromUID
        storage.accounts[request.toUID]?.pairID = pairID
        storage.pairs[pairID, default: StoredStats()].pairedAt = .now
        storage.requests[request.id] = nil
        commit()
    }

    func deleteRequest(_ request: LoveRequest) async throws {
        storage.requests[request.id] = nil
        commit()
    }

    func unpair(uid: String) async throws {
        guard let loveUID = storage.accounts[uid]?.partnerUID else { throw AccountError.notPaired }
        storage.accounts[uid]?.partnerUID = nil
        storage.accounts[uid]?.pairID = nil
        if storage.accounts[loveUID]?.partnerUID == uid {
            storage.accounts[loveUID]?.partnerUID = nil
            storage.accounts[loveUID]?.pairID = nil
        }
        commit()
    }

    func recordGame(pairID: String, seconds: Double, day: String) async throws {
        var stats = storage.pairs[pairID, default: StoredStats()]
        stats.gamesPlayed += 1
        stats.secondsPlayed += seconds
        if !stats.playDays.contains(day) { stats.playDays.append(day) }
        stats.lastPlayedAt = .now
        storage.pairs[pairID] = stats
        commit()
    }

    func setOnline(uid: String, _ online: Bool) async {
        storage.accounts[uid]?.lastOnline = .now
        storage.accounts[uid]?.online = online
        commit()
    }

    // MARK: Private

    private func account(_ uid: String) -> UserAccount? {
        guard let stored = storage.accounts[uid] else { return nil }
        return UserAccount(
            uid: uid, code: stored.code, nickname: stored.nickname, email: stored.email, avatar: stored.avatar,
            partnerUID: stored.partnerUID, pairID: stored.pairID, lastOnline: stored.lastOnline,
            online: stored.online ?? false
        )
    }

    private func stats(_ pairID: String) -> CoupleStats? {
        guard let stored = storage.pairs[pairID] else { return nil }
        return CoupleStats(
            pairedAt: stored.pairedAt, gamesPlayed: stored.gamesPlayed, secondsPlayed: stored.secondsPlayed,
            playDays: stored.playDays, lastPlayedAt: stored.lastPlayedAt
        )
    }

    private func request(_ id: String) -> LoveRequest? {
        guard let stored = storage.requests[id],
              let from = storage.accounts[stored.from], let to = storage.accounts[stored.to] else { return nil }
        return LoveRequest(
            fromUID: stored.from, toUID: stored.to, fromNickname: from.nickname, fromCode: from.code,
            toNickname: to.nickname, toCode: to.code, createdAt: stored.createdAt
        )
    }

    private func requests(uid: String, incoming: Bool) -> [LoveRequest] {
        storage.requests
            .filter { (incoming ? $0.value.to : $0.value.from) == uid }
            .compactMap { request($0.key) }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    private static let pretendPrefix = "local-love-"

    private func createPretendLove(code: String) -> String {
        let uid = Self.pretendPrefix + code
        storage.accounts[uid] = StoredAccount(code: code, nickname: "Test Love", email: "", lastOnline: .now.addingTimeInterval(-3600))
        return uid
    }

    private func uniqueCode() -> String {
        var code = AccountCode.make()
        while storage.accounts.values.contains(where: { $0.code == code }) { code = AccountCode.make() }
        return code
    }

    private func commit() {
        save()
        // Callbacks can cancel other observers (e.g. unpairing drops the love listener),
        // so re-check each one is still registered before calling it.
        for id in Array(accountObservers.keys) {
            guard let observer = accountObservers[id] else { continue }
            observer.onChange(account(observer.uid))
        }
        for id in Array(statsObservers.keys) {
            guard let observer = statsObservers[id] else { continue }
            observer.onChange(stats(observer.pairID))
        }
        for id in Array(requestObservers.keys) {
            guard let observer = requestObservers[id] else { continue }
            observer.onChange(requests(uid: observer.uid, incoming: observer.incoming))
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(storage) { defaults.set(data, forKey: Self.key) }
    }
}

private final class LocalListener: ListenerToken {
    private let onCancel: () -> Void

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel()
    }
}
