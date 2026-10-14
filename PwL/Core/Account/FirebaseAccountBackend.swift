import FirebaseCore
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore
@preconcurrency import GoogleSignIn
import UIKit

/// Firestore layout (see `firestore.rules`):
/// - `users/{uid}`: code, nickname, email, avatar, partnerUID, pairID, online, lastOnline, createdAt
/// - `codes/{code}`: { uid } — guarantees PwL IDs are unique and lets us look them up
/// - `requests/{fromUID}_{toUID}`: from, to, fromNickname, fromCode, toNickname, toCode, createdAt
///   — a pending match request; accepting it is what lets the receiver pair the two accounts
/// - `pairs/{pairID}`: members, pairedAt, gamesPlayed, secondsPlayed, playDays, lastPlayedAt
///   (`pairID` = both uids sorted and joined by "_", so re-pairing restores history)
///
/// Firestore work happens in `nonisolated static` helpers so its background-queue
/// callbacks never run main-actor-isolated closures.
@MainActor
final class FirebaseAccountBackend: AccountBackend {
    /// Configures Firebase if `GoogleService-Info.plist` is bundled.
    static func configureIfPossible() -> Bool {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return false }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        return true
    }

    let isRemote = true

    var currentUID: String? { Auth.auth().currentUser?.uid }

    // MARK: Auth

    func signIn() async throws -> String {
        guard let clientID = FirebaseApp.app()?.options.clientID else { throw AccountError.notConfigured }
        // GoogleSignIn raises an uncatchable exception if its return URL scheme is missing.
        guard Self.hasURLScheme(Self.reversed(clientID)) else { throw AccountError.notConfigured }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let presenter = Self.topViewController() else { throw AccountError.failed("No window to present sign-in.") }

        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch let error as GIDSignInError where error.code == .canceled {
            throw AccountError.cancelled
        }
        guard let idToken = result.user.idToken?.tokenString else { throw AccountError.missingToken }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        return try await Self.firebaseSignIn(with: credential)
    }

    func signIn(code: String) async throws -> String {
        try await Self.codeSignIn(code: code)
    }

    func enableCodeSignIn(code: String) async {
        await Self.linkCodeCredential(code: code)
    }

    func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }

    // MARK: Account

    func loadOrCreateAccount(uid: String) async throws -> UserAccount {
        let user = Auth.auth().currentUser
        let nickname = user?.displayName?.split(separator: " ").first.map(String.init) ?? "Lover"
        return try await Self.loadOrCreate(uid: uid, nickname: nickname, email: user?.email ?? "")
    }

    func observeAccount(uid: String, onChange: @escaping @MainActor @Sendable (UserAccount?) -> Void) -> ListenerToken {
        FirestoreListener(Self.listenUser(uid: uid, onChange: onChange))
    }

    func observeStats(pairID: String, onChange: @escaping @MainActor @Sendable (CoupleStats?) -> Void) -> ListenerToken {
        FirestoreListener(Self.listenPair(pairID: pairID, onChange: onChange))
    }

    func updateNickname(uid: String, nickname: String) async throws {
        try await Self.update(uid: uid, fields: ["nickname": nickname])
    }

    func updateAvatar(uid: String, avatar: Data?) async throws {
        try await Self.update(uid: uid, fields: ["avatar": avatar ?? FieldValue.delete()])
    }

    func observeRequests(uid: String, incoming: Bool, onChange: @escaping @MainActor @Sendable ([LoveRequest]) -> Void) -> ListenerToken {
        FirestoreListener(Self.listenRequests(uid: uid, incoming: incoming, onChange: onChange))
    }

    func sendRequest(from me: UserAccount, toCode code: String) async throws -> Bool {
        try await Self.sendRequest(from: me, toCode: code)
    }

    func acceptRequest(_ request: LoveRequest) async throws {
        try await Self.acceptTransaction(request)
    }

    func deleteRequest(_ request: LoveRequest) async throws {
        try await Self.requests().document(request.id).delete()
    }

    func unpair(uid: String) async throws {
        try await Self.unpairTransaction(uid: uid)
    }

    func recordGame(pairID: String, seconds: Double, day: String) async throws {
        try await Self.incrementStats(pairID: pairID, seconds: seconds, day: day)
    }

    func setOnline(uid: String, _ online: Bool) async {
        // Going offline happens as the app is backgrounded; ask iOS for time to finish the write.
        let task = UIApplication.shared.beginBackgroundTask(withName: "pwl.presence")
        defer { if task != .invalid { UIApplication.shared.endBackgroundTask(task) } }
        try? await Self.update(uid: uid, fields: ["online": online, "lastOnline": FieldValue.serverTimestamp()])
    }

    // MARK: Firestore helpers (nonisolated)

    private nonisolated static var db: Firestore { Firestore.firestore() }
    private nonisolated static func users() -> CollectionReference { db.collection("users") }
    private nonisolated static func codes() -> CollectionReference { db.collection("codes") }
    private nonisolated static func pairs() -> CollectionReference { db.collection("pairs") }
    private nonisolated static func requests() -> CollectionReference { db.collection("requests") }

    private nonisolated static func firebaseSignIn(with credential: AuthCredential) async throws -> String {
        try await Auth.auth().signIn(with: credential).user.uid
    }

    // PwL ID sign-in rides on Firebase's Email/Password provider: each account gets a
    // hidden email/password credential derived from its code, linked to the same uid.
    private nonisolated static func codeEmail(_ code: String) -> String { "\(code.lowercased())@id.pwl.invalid" }
    private nonisolated static func codePassword(_ code: String) -> String { "pwl-id-\(code)" }

    private nonisolated static func codeSignIn(code: String) async throws -> String {
        do {
            return try await Auth.auth().signIn(withEmail: codeEmail(code), password: codePassword(code)).user.uid
        } catch {
            switch AuthErrorCode(rawValue: (error as NSError).code) {
            case .operationNotAllowed: throw AccountError.codeSignInNotEnabled
            case .userNotFound, .invalidCredential, .wrongPassword, .invalidEmail: throw AccountError.codeNotFound
            default: throw error
            }
        }
    }

    private nonisolated static func linkCodeCredential(code: String) async {
        guard let user = Auth.auth().currentUser,
              !user.providerData.contains(where: { $0.providerID == EmailAuthProviderID }) else { return }
        let credential = EmailAuthProvider.credential(withEmail: codeEmail(code), password: codePassword(code))
        // Fails harmlessly if the provider is off or the credential is already linked.
        _ = try? await user.link(with: credential)
    }

    private nonisolated static func loadOrCreate(uid: String, nickname: String, email: String) async throws -> UserAccount {
        let userRef = users().document(uid)
        let snapshot = try await userRef.getDocument()
        if let data = snapshot.data(), let account = account(uid: uid, data: data) {
            return account
        }

        // First sign-in: reserve a unique code and create the user in one transaction.
        for _ in 0..<6 {
            let code = AccountCode.make()
            let codeRef = codes().document(code)
            let fields: [String: Any] = [
                "code": code,
                "nickname": nickname,
                "email": email,
                "createdAt": FieldValue.serverTimestamp(),
                "lastOnline": FieldValue.serverTimestamp(),
            ]
            do {
                _ = try await db.runTransaction { transaction, errorPointer in
                    do {
                        if try transaction.getDocument(codeRef).exists {
                            errorPointer?.pointee = AccountError.codeTaken as NSError
                            return nil
                        }
                    } catch {
                        errorPointer?.pointee = error as NSError
                        return nil
                    }
                    transaction.setData(["uid": uid], forDocument: codeRef)
                    transaction.setData(fields, forDocument: userRef)
                    return nil
                }
                return UserAccount(uid: uid, code: code, nickname: nickname, email: email, lastOnline: .now)
            } catch let error as AccountError where error == .codeTaken {
                continue
            }
        }
        throw AccountError.codeTaken
    }

    private nonisolated static func update(uid: String, fields: [String: Any]) async throws {
        try await users().document(uid).updateData(fields)
    }

    private nonisolated static func sendRequest(from me: UserAccount, toCode code: String) async throws -> Bool {
        guard let loveUID = try await codes().document(code).getDocument().data()?["uid"] as? String else {
            throw AccountError.codeNotFound
        }
        guard loveUID != me.uid else { throw AccountError.cannotPairWithSelf }
        guard let loveData = try await users().document(loveUID).getDocument().data(),
              let love = account(uid: loveUID, data: loveData) else { throw AccountError.codeNotFound }
        guard !love.isPaired else { throw AccountError.loveAlreadyPaired }

        // They already asked us: accepting theirs is what both of us want.
        let reverse = try await requests().document(LoveRequest.id(from: loveUID, to: me.uid)).getDocument()
        if let data = reverse.data(), let theirs = request(data: data) {
            try await acceptTransaction(theirs)
            return true
        }

        // One outgoing request at a time: replace any earlier one.
        let newID = LoveRequest.id(from: me.uid, to: loveUID)
        for old in try await requests().whereField("from", isEqualTo: me.uid).getDocuments().documents where old.documentID != newID {
            try await old.reference.delete()
        }
        try await requests().document(newID).setData([
            "from": me.uid,
            "to": loveUID,
            "fromNickname": me.nickname,
            "fromCode": me.code,
            "toNickname": love.nickname,
            "toCode": love.code,
            "createdAt": FieldValue.serverTimestamp(),
        ])
        return false
    }

    /// Run by the request's receiver. `firestore.rules` only lets them set the sender's
    /// `partnerUID` while this request exists.
    private nonisolated static func acceptTransaction(_ request: LoveRequest) async throws {
        let fromUID = request.fromUID, toUID = request.toUID
        let pairID = [fromUID, toUID].sorted().joined(separator: "_")
        let fromRef = users().document(fromUID)
        let toRef = users().document(toUID)
        let requestRef = requests().document(request.id)
        let pairRef = pairs().document(pairID)

        do {
            _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    guard try transaction.getDocument(requestRef).exists else {
                        errorPointer?.pointee = AccountError.requestGone as NSError
                        return nil
                    }
                    if try transaction.getDocument(toRef).data()?["partnerUID"] is String {
                        errorPointer?.pointee = AccountError.alreadyPaired as NSError
                        return nil
                    }
                    if try transaction.getDocument(fromRef).data()?["partnerUID"] is String {
                        errorPointer?.pointee = AccountError.loveAlreadyPaired as NSError
                        return nil
                    }
                    // Re-pairing keeps the old stats document (and its members list).
                    if try transaction.getDocument(pairRef).exists {
                        transaction.updateData(["pairedAt": FieldValue.serverTimestamp()], forDocument: pairRef)
                    } else {
                        transaction.setData(
                            ["members": [fromUID, toUID].sorted(), "pairedAt": FieldValue.serverTimestamp()],
                            forDocument: pairRef
                        )
                    }
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
                transaction.updateData(["partnerUID": fromUID, "pairID": pairID], forDocument: toRef)
                transaction.updateData(["partnerUID": toUID, "pairID": pairID], forDocument: fromRef)
                transaction.deleteDocument(requestRef)
                return nil
            }
        } catch AccountError.loveAlreadyPaired {
            // The sender matched someone else meanwhile; the request is stale.
            try? await requestRef.delete()
            throw AccountError.loveAlreadyPaired
        }
    }

    private nonisolated static func unpairTransaction(uid: String) async throws {
        let meRef = users().document(uid)
        let cleared: [String: Any] = ["partnerUID": FieldValue.delete(), "pairID": FieldValue.delete()]

        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                guard let loveUID = try transaction.getDocument(meRef).data()?["partnerUID"] as? String else {
                    errorPointer?.pointee = AccountError.notPaired as NSError
                    return nil
                }
                let loveRef = users().document(loveUID)
                let love = try transaction.getDocument(loveRef)
                transaction.updateData(cleared, forDocument: meRef)
                if love.data()?["partnerUID"] as? String == uid {
                    transaction.updateData(cleared, forDocument: loveRef)
                }
            } catch {
                errorPointer?.pointee = error as NSError
            }
            return nil
        }
    }

    private nonisolated static func incrementStats(pairID: String, seconds: Double, day: String) async throws {
        try await pairs().document(pairID).updateData([
            "gamesPlayed": FieldValue.increment(Int64(1)),
            "secondsPlayed": FieldValue.increment(seconds),
            "playDays": FieldValue.arrayUnion([day]),
            "lastPlayedAt": FieldValue.serverTimestamp(),
        ])
    }

    private nonisolated static func listenUser(
        uid: String,
        onChange: @escaping @MainActor @Sendable (UserAccount?) -> Void
    ) -> ListenerRegistration {
        users().document(uid).addSnapshotListener { snapshot, _ in
            let account = snapshot?.data().flatMap { Self.account(uid: uid, data: $0) }
            Task { @MainActor in onChange(account) }
        }
    }

    private nonisolated static func listenPair(
        pairID: String,
        onChange: @escaping @MainActor @Sendable (CoupleStats?) -> Void
    ) -> ListenerRegistration {
        pairs().document(pairID).addSnapshotListener { snapshot, _ in
            let stats = snapshot?.data().map(Self.stats(from:))
            Task { @MainActor in onChange(stats) }
        }
    }

    private nonisolated static func listenRequests(
        uid: String,
        incoming: Bool,
        onChange: @escaping @MainActor @Sendable ([LoveRequest]) -> Void
    ) -> ListenerRegistration {
        requests().whereField(incoming ? "to" : "from", isEqualTo: uid).addSnapshotListener { snapshot, _ in
            let list = (snapshot?.documents ?? [])
                .compactMap { request(data: $0.data()) }
                .sorted { ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture) }
            Task { @MainActor in onChange(list) }
        }
    }

    private nonisolated static func request(data: [String: Any]) -> LoveRequest? {
        guard let from = data["from"] as? String, let to = data["to"] as? String else { return nil }
        return LoveRequest(
            fromUID: from,
            toUID: to,
            fromNickname: data["fromNickname"] as? String ?? "Lover",
            fromCode: data["fromCode"] as? String ?? "",
            toNickname: data["toNickname"] as? String ?? "Lover",
            toCode: data["toCode"] as? String ?? "",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    private nonisolated static func account(uid: String, data: [String: Any]) -> UserAccount? {
        guard let code = data["code"] as? String else { return nil }
        return UserAccount(
            uid: uid,
            code: code,
            nickname: data["nickname"] as? String ?? "Lover",
            email: data["email"] as? String ?? "",
            avatar: data["avatar"] as? Data,
            partnerUID: data["partnerUID"] as? String,
            pairID: data["pairID"] as? String,
            lastOnline: (data["lastOnline"] as? Timestamp)?.dateValue(),
            online: data["online"] as? Bool ?? false
        )
    }

    private nonisolated static func stats(from data: [String: Any]) -> CoupleStats {
        CoupleStats(
            pairedAt: (data["pairedAt"] as? Timestamp)?.dateValue(),
            gamesPlayed: (data["gamesPlayed"] as? NSNumber)?.intValue ?? 0,
            secondsPlayed: (data["secondsPlayed"] as? NSNumber)?.doubleValue ?? 0,
            playDays: data["playDays"] as? [String] ?? [],
            lastPlayedAt: (data["lastPlayedAt"] as? Timestamp)?.dateValue()
        )
    }

    /// "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc"
    private static func reversed(_ clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    private static func hasURLScheme(_ scheme: String) -> Bool {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains(scheme) == true }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

private final class FirestoreListener: ListenerToken {
    private let registration: ListenerRegistration

    init(_ registration: ListenerRegistration) {
        self.registration = registration
    }

    func cancel() {
        registration.remove()
    }
}
