import Foundation

/// A signed-in PwL user (Firestore `users/{uid}`).
struct UserAccount: Equatable, Sendable {
    let uid: String
    /// Unique 8-character PwL ID, used to match with a love.
    var code: String
    var nickname: String
    var email: String
    /// Small JPEG (≤ 256px), stored inline.
    var avatar: Data?
    var partnerUID: String?
    var pairID: String?
    /// Last presence update (heartbeat while the app is open, or when it was left).
    var lastOnline: Date?
    /// The app is open on screen. Goes `false` when the app is left or the user signs out.
    var online = false

    var isPaired: Bool { partnerUID != nil }

    /// How often an open app refreshes `lastOnline`.
    static let heartbeat: TimeInterval = 30

    /// Online only while the app is open *and* its heartbeat is fresh, so a force-quit
    /// or lost connection shows as offline after a few missed beats.
    func isOnline(at now: Date = .now) -> Bool {
        guard online, let lastOnline else { return false }
        return now.timeIntervalSince(lastOnline) < Self.heartbeat * 2.5
    }
}

/// Shared metrics for a couple (Firestore `pairs/{pairID}`).
struct CoupleStats: Equatable, Sendable {
    var pairedAt: Date?
    var gamesPlayed = 0
    var secondsPlayed: Double = 0
    /// Local calendar days ("yyyy-MM-dd") on which the couple played.
    var playDays: [String] = []
    var lastPlayedAt: Date?

    var daysPlayed: Int { Set(playDays).count }
    var minutesPlayed: Int { Int(secondsPlayed / 60) }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// A pending "be my love" request (Firestore `requests/{from}_{to}`). The receiver
/// accepts (which pairs them) or declines; the sender can cancel it.
struct LoveRequest: Identifiable, Equatable, Sendable {
    let fromUID: String
    let toUID: String
    var fromNickname: String
    var fromCode: String
    var toNickname: String
    var toCode: String
    var createdAt: Date?

    var id: String { Self.id(from: fromUID, to: toUID) }

    static func id(from: String, to: String) -> String { "\(from)_\(to)" }
}

/// The 8-character PwL ID. Uses an alphabet without look-alikes (no 0/O, 1/I/L).
enum AccountCode {
    static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")
    static let length = 8

    static func make(using rng: inout some RandomNumberGenerator) -> String {
        String((0..<length).map { _ in alphabet.randomElement(using: &rng)! })
    }

    static func make() -> String {
        var rng = SystemRandomNumberGenerator()
        return make(using: &rng)
    }

    /// Uppercases and strips spaces / dashes so "ab12-cd34" matches "AB12CD34".
    static func normalize(_ input: String) -> String {
        input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    }

    static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy(alphabet.contains)
    }

    /// "AB12CD34" → "AB12 CD34" for display.
    static func formatted(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(4)) \(code.suffix(4))"
    }
}

enum AccountError: LocalizedError, Equatable {
    case notConfigured
    case cancelled
    case missingToken
    case invalidCode
    case codeNotFound
    case cannotPairWithSelf
    case alreadyPaired
    case loveAlreadyPaired
    case notPaired
    case requestGone
    case codeTaken
    case codeSignInNotEnabled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Sign-in isn't set up yet."
        case .cancelled: "Sign-in was cancelled."
        case .missingToken: "Google didn't return a sign-in token. Please try again."
        case .invalidCode: "A PwL ID has 8 letters and numbers."
        case .codeNotFound: "No one has that PwL ID. Check it and try again."
        case .cannotPairWithSelf: "That's your own ID — ask your love for theirs 💕"
        case .alreadyPaired: "You're already matched. Unpair first to match someone else."
        case .loveAlreadyPaired: "That person is already matched with someone else."
        case .notPaired: "You're not matched with anyone."
        case .requestGone: "That request isn't there anymore."
        case .codeTaken: "Couldn't create a unique ID. Please try again."
        case .codeSignInNotEnabled: "Signing in with a PwL ID isn't turned on yet. Use Google for now."
        case .failed(let message): message
        }
    }
}

/// Cancels a realtime listener.
@MainActor
protocol ListenerToken: AnyObject {
    func cancel()
}

/// Everything the app needs from the account backend (Firebase in production,
/// `LocalAccountBackend` for tests / before Firebase is configured).
@MainActor
protocol AccountBackend: AnyObject {
    /// `false` = local test backend (no real Google sign-in).
    var isRemote: Bool { get }
    /// Already signed in from a previous launch.
    var currentUID: String? { get }

    func signIn() async throws -> String
    /// Signs in with a PwL ID alone. Works once that account has signed in with Google
    /// at least once (see `enableCodeSignIn`).
    func signIn(code: String) async throws -> String
    func signOut() throws
    /// Lets this account sign in later with just its PwL ID. Safe to call repeatedly.
    func enableCodeSignIn(code: String) async
    /// Loads the user's account, creating it (with a fresh unique PwL ID) on first sign-in.
    func loadOrCreateAccount(uid: String) async throws -> UserAccount

    func observeAccount(uid: String, onChange: @escaping @MainActor @Sendable (UserAccount?) -> Void) -> ListenerToken
    func observeStats(pairID: String, onChange: @escaping @MainActor @Sendable (CoupleStats?) -> Void) -> ListenerToken

    func updateNickname(uid: String, nickname: String) async throws
    func updateAvatar(uid: String, avatar: Data?) async throws

    /// Live requests sent to (`incoming`) or by this user.
    func observeRequests(uid: String, incoming: Bool, onChange: @escaping @MainActor @Sendable ([LoveRequest]) -> Void) -> ListenerToken
    /// Asks the owner of `code` to be your love. Both must be unpaired. If they already
    /// asked you, this accepts their request instead and returns `true` (now paired).
    func sendRequest(from me: UserAccount, toCode code: String) async throws -> Bool
    /// Pairs the two people in `request`; only its receiver can accept. Both must be unpaired.
    func acceptRequest(_ request: LoveRequest) async throws
    /// Declines (receiver) or cancels (sender) a request.
    func deleteRequest(_ request: LoveRequest) async throws
    /// Clears the match on both accounts. Shared stats are kept for if they re-pair.
    func unpair(uid: String) async throws

    func recordGame(pairID: String, seconds: Double, day: String) async throws
    /// Marks the user as in the app (and refreshes `lastOnline`) or as gone.
    func setOnline(uid: String, _ online: Bool) async
}
