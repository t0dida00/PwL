import Foundation
import Testing
@testable import PwL

struct AccountCodeTests {
    @Test
    func generatedCodesAreValidAndAvoidLookAlikes() {
        var rng = SeededGenerator(seed: 3)
        for _ in 0..<500 {
            let code = AccountCode.make(using: &rng)
            #expect(AccountCode.isValid(code))
            #expect(!code.contains { "01OIL".contains($0) })
        }
    }

    @Test
    func normalizeAcceptsSpacesDashesAndLowercase() {
        #expect(AccountCode.normalize(" ab2c-de3f gh ") == "AB2CDE3FGH")
        #expect(AccountCode.isValid(AccountCode.normalize("ab2c de3f")))
        #expect(!AccountCode.isValid("AB2CDE3"))
        #expect(!AccountCode.isValid("AB2CDE30"))
    }

    @Test
    func formattedSplitsInTheMiddle() {
        #expect(AccountCode.formatted("AB2CDE3F") == "AB2C DE3F")
    }

    @Test
    func dayKeyIsStable() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_760_400_000) // 2025-10-14
        #expect(CoupleStats.dayKey(for: date, calendar: calendar) == "2025-10-14")
    }
}

struct PresenceTests {
    private let now = Date(timeIntervalSince1970: 1_760_400_000)

    private func user(online: Bool, secondsAgo: TimeInterval?) -> UserAccount {
        UserAccount(
            uid: "u", code: "ABCD2345", nickname: "Linh", email: "",
            lastOnline: secondsAgo.map { now.addingTimeInterval(-$0) }, online: online
        )
    }

    @Test
    func onlineOnlyWhileAppOpenWithFreshHeartbeat() {
        #expect(user(online: true, secondsAgo: 30).isOnline(at: now))
        // Left the app (backgrounded) a moment ago: offline right away.
        #expect(!user(online: false, secondsAgo: 5).isOnline(at: now))
        // App killed without saying goodbye: offline once heartbeats stop.
        #expect(!user(online: true, secondsAgo: UserAccount.heartbeat * 3).isOnline(at: now))
    }

    @Test
    func facebookStyleText() {
        #expect(LastSeenFormat.presence(user(online: true, secondsAgo: 10), now: now) == "Online now")
        #expect(LastSeenFormat.presence(user(online: false, secondsAgo: 20), now: now) == "Active just now")
        #expect(LastSeenFormat.presence(user(online: false, secondsAgo: 5 * 60), now: now) == "Active 5m ago")
        #expect(LastSeenFormat.presence(user(online: false, secondsAgo: 3 * 3600), now: now) == "Active 3h ago")
        #expect(LastSeenFormat.presence(user(online: false, secondsAgo: 2 * 86_400), now: now) == "Active 2d ago")
        #expect(LastSeenFormat.presence(user(online: false, secondsAgo: nil), now: now) == "Offline")
    }
}

@MainActor
struct AccountStoreTests {
    /// Pretend loves never answer, so tests decide every accept / decline.
    private func makeBackend() -> LocalAccountBackend {
        LocalAccountBackend(defaults: UserDefaults(suiteName: "PwLTests.\(UUID().uuidString)")!, pretendLoveReplyDelay: nil)
    }

    private func signedInStore(backend: LocalAccountBackend? = nil) async -> AccountStore {
        let store = AccountStore(backend: backend ?? makeBackend())
        if backend == nil {
            await store.restore()
            #expect(store.state == .signedOut)
        }
        await store.signIn()
        return store
    }

    /// Two real accounts on one backend: `me` asks, `love` accepts.
    private func matchedStores() async -> (me: AccountStore, love: AccountStore) {
        let backend = makeBackend()
        let me = await signedInStore(backend: backend)
        let love = await signedInStore(backend: backend)
        await me.requestMatch(withCode: love.account!.code)
        await love.accept(love.incomingRequests[0])
        return (me, love)
    }

    @Test
    func firstSignInCreatesAccountWithUniqueID() async {
        let store = await signedInStore()
        #expect(store.state == .signedIn)
        #expect(AccountCode.isValid(store.account?.code ?? ""))
        #expect(store.isPaired == false)
    }

    @Test
    func requestValidation() async {
        let store = await signedInStore()
        let myCode = store.account!.code

        #expect(await store.requestMatch(withCode: "abc") == false)
        #expect(store.errorMessage == AccountError.invalidCode.errorDescription)

        #expect(await store.requestMatch(withCode: myCode) == false)
        #expect(store.errorMessage == AccountError.cannotPairWithSelf.errorDescription)

        // Sending doesn't match you; it waits for an answer.
        #expect(await store.requestMatch(withCode: "ABCD2345"))
        #expect(!store.isPaired)
        #expect(store.outgoingRequest?.toCode == "ABCD2345")

        // One outgoing request at a time: a new one replaces it.
        #expect(await store.requestMatch(withCode: "WXYZ6789"))
        #expect(store.outgoingRequest?.toCode == "WXYZ6789")

        #expect(await store.cancelOutgoingRequest())
        #expect(store.outgoingRequest == nil)
    }

    @Test
    func loveMustAcceptBeforeMatching() async {
        let backend = makeBackend()
        let me = await signedInStore(backend: backend)
        let love = await signedInStore(backend: backend)

        await me.requestMatch(withCode: love.account!.code)
        #expect(love.incomingRequests.map(\.fromUID) == [me.account!.uid])
        #expect(!me.isPaired && !love.isPaired)

        #expect(await love.decline(love.incomingRequests[0]))
        #expect(love.incomingRequests.isEmpty)
        #expect(me.outgoingRequest == nil)
        #expect(!me.isPaired && !love.isPaired)

        await me.requestMatch(withCode: love.account!.code)
        #expect(await love.accept(love.incomingRequests[0]))
        #expect(me.isPaired && love.isPaired)
        #expect(me.love?.uid == love.account?.uid)
        #expect(love.love?.uid == me.account?.uid)
        #expect(me.outgoingRequest == nil)
        #expect(love.incomingRequests.isEmpty)
    }

    @Test
    func askingSomeoneWhoAskedYouMatchesRightAway() async {
        let backend = makeBackend()
        let me = await signedInStore(backend: backend)
        let love = await signedInStore(backend: backend)

        await love.requestMatch(withCode: me.account!.code)
        #expect(await me.requestMatch(withCode: love.account!.code))
        #expect(me.isPaired && love.isPaired)
    }

    @Test
    func oneLoveAtATime() async {
        let (me, love) = await matchedStores()
        let other = await signedInStore(backend: me.backend as? LocalAccountBackend)

        #expect(await me.requestMatch(withCode: other.account!.code) == false)
        #expect(me.errorMessage == AccountError.alreadyPaired.errorDescription)

        #expect(await other.requestMatch(withCode: love.account!.code) == false)
        #expect(other.errorMessage == AccountError.loveAlreadyPaired.errorDescription)

        #expect(await me.unpair())
        #expect(!me.isPaired && !love.isPaired)
        #expect(me.love == nil)
    }

    @Test
    func staleRequestCannotBeAccepted() async {
        let backend = makeBackend()
        let me = await signedInStore(backend: backend)
        let love = await signedInStore(backend: backend)
        let other = await signedInStore(backend: backend)

        await me.requestMatch(withCode: love.account!.code)
        let request = love.incomingRequests[0]
        await me.cancelOutgoingRequest()

        #expect(await love.accept(request) == false)
        #expect(love.errorMessage == AccountError.requestGone.errorDescription)
        #expect(!love.isPaired)

        // Asker matched someone else in the meantime.
        await me.requestMatch(withCode: love.account!.code)
        let pending = love.incomingRequests[0]
        await other.requestMatch(withCode: me.account!.code)
        await me.accept(me.incomingRequests[0])
        #expect(await love.accept(pending) == false)
        #expect(!love.isPaired)
    }

    @Test
    func recordedGamesFeedTheDashboard() async {
        let (store, love) = await matchedStores()
        let day = Date(timeIntervalSince1970: 1_760_400_000)

        await store.recordGame(seconds: 90, at: day)
        await store.recordGame(seconds: 45, at: day)
        await store.recordGame(seconds: 30, at: day.addingTimeInterval(86_400))

        #expect(store.stats?.gamesPlayed == 3)
        #expect(store.stats?.minutesPlayed == 2)
        #expect(store.stats?.daysPlayed == 2)
        #expect(love.stats?.gamesPlayed == 3)
    }

    @Test
    func rePairingRestoresSharedStats() async {
        let (store, love) = await matchedStores()
        await store.recordGame(seconds: 60)
        await store.unpair()
        await love.requestMatch(withCode: store.account!.code)
        await store.accept(store.incomingRequests[0])
        #expect(store.stats?.gamesPlayed == 1)
    }

    @Test
    func signInWithPwLIDOpensTheSameAccount() async {
        let store = await signedInStore()
        let account = store.account!
        await store.signOut()

        await store.signIn(withCode: "abc")
        #expect(store.state == .signedOut)
        #expect(store.errorMessage == AccountError.invalidCode.errorDescription)

        await store.signIn(withCode: "WXYZ6789")
        #expect(store.state == .signedOut)
        #expect(store.errorMessage == AccountError.codeNotFound.errorDescription)

        await store.signIn(withCode: AccountCode.formatted(account.code).lowercased())
        #expect(store.state == .signedIn)
        #expect(store.account?.uid == account.uid)
        #expect(store.account?.code == account.code)
    }

    @Test
    func leavingTheAppShowsOffline() async {
        let backend = makeBackend()
        let me = await signedInStore(backend: backend)
        let love = await signedInStore(backend: backend)
        await me.requestMatch(withCode: love.account!.code)
        await love.accept(love.incomingRequests[0])
        await Task.yield()
        #expect(me.love?.isOnline() == true)

        await love.appWentToBackground()
        #expect(me.love?.isOnline() == false)

        await love.signOut()
        #expect(me.love?.online == false)
    }

    @Test
    func profileUpdatesAndSignOut() async {
        let store = await signedInStore()
        #expect(await store.updateNickname("  Khoa  "))
        #expect(store.account?.nickname == "Khoa")
        #expect(await store.updateNickname("   ") == false)

        await store.signOut()
        #expect(store.state == .signedOut)
        #expect(store.account == nil)
    }
}
