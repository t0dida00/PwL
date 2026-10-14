@preconcurrency import MultipeerConnectivity
import Observation

/// Connects two nearby devices (Wi-Fi / Bluetooth, no server) with MultipeerConnectivity.
///
/// One player hosts a room, the other browses and joins. Only the matched love's room is
/// shown, and the host only accepts their love (account uids are exchanged in discovery
/// info / invitation context). Once connected, games exchange
/// their own Codable messages through `send(_:)` / `onGameMessage`. The service itself
/// only knows about the lobby-level `hello` (partner name exchange).
@MainActor
@Observable
final class NearbyService {
    enum Role {
        case host
        case guest
    }

    enum Status: Equatable {
        case idle
        case hosting
        case browsing
        case connecting(String)
        case connected
        /// Was connected, then the link dropped.
        case lost
    }

    struct NearbyHost: Identifiable, Hashable {
        let name: String
        fileprivate let peer: MCPeerID
        var id: MCPeerID { peer }
    }

    private enum Envelope: Codable {
        case hello(name: String)
        case game(Data)
    }

    static let serviceType = "pwl-game"

    private(set) var status: Status = .idle
    private(set) var role: Role?
    private(set) var hosts: [NearbyHost] = []
    private(set) var partnerName: String?

    /// Receives game-level payloads. The screen currently driving the match sets this.
    @ObservationIgnored var onGameMessage: ((Data) -> Void)?

    @ObservationIgnored private var session: MCSession?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var delegate: Delegate?
    @ObservationIgnored private var localName = ""
    @ObservationIgnored private var localUID = ""
    /// Account uid of the matched love — the only peer we show / accept.
    @ObservationIgnored private var loveUID = ""

    var isConnected: Bool { status == .connected }
    var isHost: Bool { role == .host }

    func host(as name: String, uid: String, loveUID: String) {
        stop()
        let peer = setUp(name: name, uid: uid, loveUID: loveUID)
        role = .host
        let advertiser = MCNearbyServiceAdvertiser(
            peer: peer,
            discoveryInfo: ["name": localName, "uid": uid],
            serviceType: Self.serviceType
        )
        advertiser.delegate = delegate
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        status = .hosting
    }

    func browse(as name: String, uid: String, loveUID: String) {
        stop()
        let peer = setUp(name: name, uid: uid, loveUID: loveUID)
        role = .guest
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        browser.delegate = delegate
        browser.startBrowsingForPeers()
        self.browser = browser
        status = .browsing
    }

    func join(_ host: NearbyHost) {
        guard let session, let browser else { return }
        browser.invitePeer(host.peer, to: session, withContext: Data(localUID.utf8), timeout: 20)
        status = .connecting(host.name)
    }

    /// Leaves the room and tears everything down.
    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        delegate = nil
        role = nil
        hosts = []
        partnerName = nil
        status = .idle
    }

    func send<Message: Encodable>(_ message: Message) {
        guard let payload = try? JSONEncoder().encode(message) else { return }
        sendEnvelope(.game(payload))
    }

    // MARK: Private

    private func setUp(name: String, uid: String, loveUID: String) -> MCPeerID {
        localName = name
        localUID = uid
        self.loveUID = loveUID
        let peer = MCPeerID(displayName: String(name.prefix(60)))
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        let delegate = Delegate(owner: self)
        session.delegate = delegate
        self.session = session
        self.delegate = delegate
        return peer
    }

    private func sendEnvelope(_ envelope: Envelope) {
        guard let session, !session.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(envelope) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    // MARK: Delegate callbacks (hopped to the main actor)

    fileprivate func peer(_ peer: MCPeerID, changedTo state: MCSessionState) {
        switch state {
        case .connected:
            advertiser?.stopAdvertisingPeer()
            browser?.stopBrowsingForPeers()
            partnerName = partnerName ?? peer.displayName
            status = .connected
            sendEnvelope(.hello(name: localName))
        case .connecting:
            if role == .host { status = .connecting(peer.displayName) }
        case .notConnected:
            switch status {
            case .connected:
                status = .lost
            case .connecting where role == .guest:
                status = .browsing
            case .connecting:
                status = .hosting
            default:
                break
            }
        @unknown default:
            break
        }
    }

    fileprivate func received(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
        switch envelope {
        case .hello(let name):
            partnerName = name
        case .game(let payload):
            onGameMessage?(payload)
        }
    }

    fileprivate func found(_ peer: MCPeerID, name: String, uid: String?) {
        guard uid == loveUID, !hosts.contains(where: { $0.peer == peer }) else { return }
        hosts.append(NearbyHost(name: name, peer: peer))
    }

    fileprivate func lost(_ peer: MCPeerID) {
        hosts.removeAll { $0.peer == peer }
    }

    fileprivate func invitation(from peer: MCPeerID, uid: String?, reply: (Bool, MCSession?) -> Void) {
        // Only your matched love, and only one of them.
        guard role == .host, uid == loveUID, let session, session.connectedPeers.isEmpty else {
            reply(false, nil)
            return
        }
        reply(true, session)
    }
}

/// Wraps non-Sendable MultipeerConnectivity values for the hop to the main actor.
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
}

/// MultipeerConnectivity calls these on its own queues; everything is forwarded to the main actor.
private final class Delegate: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, @unchecked Sendable {
    weak var owner: NearbyService?

    init(owner: NearbyService) {
        self.owner = owner
    }

    // MARK: MCSessionDelegate

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let peer = Unchecked(value: peerID)
        Task { @MainActor [owner] in owner?.peer(peer.value, changedTo: state) }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [owner] in owner?.received(data) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    // MARK: MCNearbyServiceAdvertiserDelegate

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let peer = Unchecked(value: peerID)
        let handler = Unchecked(value: invitationHandler)
        let uid = context.flatMap { String(data: $0, encoding: .utf8) }
        Task { @MainActor [owner] in
            guard let owner else { return handler.value(false, nil) }
            owner.invitation(from: peer.value, uid: uid) { handler.value($0, $1) }
        }
    }

    // MARK: MCNearbyServiceBrowserDelegate

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let peer = Unchecked(value: peerID)
        let name = info?["name"] ?? peerID.displayName
        let uid = info?["uid"]
        Task { @MainActor [owner] in owner?.found(peer.value, name: name, uid: uid) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peer = Unchecked(value: peerID)
        Task { @MainActor [owner] in owner?.lost(peer.value) }
    }
}
