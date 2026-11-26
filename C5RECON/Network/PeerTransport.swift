@preconcurrency import Network
import Combine
import Foundation

enum PeerTransportState: Equatable {
    case idle
    case searching
    case listening
    case peerFound(String)
    case connecting
    case ready
    case waiting(String)
    case failed(String)
    case cancelled
}

struct ReceivedPeerMessage: Sendable {
    let kind: MessageKind
    let data: Data
}

@MainActor
final class PeerTransport: ObservableObject {
    static let serviceType = "_c5recon._tcp"

    @Published private(set) var state: PeerTransportState = .idle

    nonisolated(unsafe) var onMessage: (@Sendable (ReceivedPeerMessage) -> Void)?
    var onStateChange: ((PeerTransportState) -> Void)?

    nonisolated(unsafe) private var browser: NWBrowser?
    nonisolated(unsafe) private var listener: NWListener?
    nonisolated(unsafe) private var connection: NWConnection?

    private let browserQueue = DispatchQueue(label: "recon.network.browser")
    private let listenerQueue = DispatchQueue(label: "recon.network.listener")
    private let connectionQueue = DispatchQueue(label: "recon.network.connection")
    private var activeRole: DeviceRole?

    func start(for role: DeviceRole) {
        cancel()
        activeRole = role
        switch role {
        case .camera:
            startListening()
        case .monitor:
            startBrowsing()
        }
    }

    func cancel() {
        browser?.cancel()
        listener?.cancel()
        connection?.cancel()
        browser = nil
        listener = nil
        connection = nil
        activeRole = nil
        publish(.cancelled)
    }

    func refreshAfterForegroundTransition() {
        guard let activeRole else { return }

        switch activeRole {
        case .camera where listener?.state == .ready:
            RECONDiagnostics.emit("transport_refresh", detail: "listener=ready action=keep")
        case .monitor where browser?.state == .ready:
            RECONDiagnostics.emit("transport_refresh", detail: "browser=ready action=reprocess")
            processBrowserResults(browser?.browseResults ?? [])
        default:
            RECONDiagnostics.emit("transport_refresh", detail: "role=\(activeRole.rawValue) action=restart")
            start(for: activeRole)
        }
    }

    func send(_ data: Data, kind: MessageKind) async throws {
        guard let connection else { throw TransportError.notConnected }

        let message = NWProtocolFramer.Message(kind: kind)
        let context = NWConnection.ContentContext(identifier: "recon-\(kind.rawValue)", metadata: [message])

        try await withCheckedThrowingContinuation { continuation in
            connection.send(
                content: data,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        } as Void
    }

    private func startBrowsing() {
        browser?.cancel()
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .recOnTCP)
        self.browser = browser
        publish(.searching)

        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.processBrowserResults(browser.browseResults)
            case let .waiting(error):
                self.publishFromNetworkQueue(.waiting(error.localizedDescription))
            case let .failed(error):
                self.publishFromNetworkQueue(.failed(error.localizedDescription))
                if Self.isDefunctDNSConnection(error) {
                    Task { @MainActor [weak self] in self?.restartBrowserAfterDefunctFailure() }
                }
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] _, _ in
            self?.processBrowserResults(browser.browseResults)
        }
        browser.start(queue: browserQueue)
    }

    private func startListening() {
        do {
            listener?.cancel()
            let listener = try NWListener(service: .init(type: Self.serviceType), using: .recOnTCP)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.publishFromNetworkQueue(.listening)
                case let .waiting(error):
                    self.publishFromNetworkQueue(.waiting(error.localizedDescription))
                case let .failed(error):
                    self.publishFromNetworkQueue(.failed(error.localizedDescription))
                    if Self.isDefunctDNSConnection(error) {
                        Task { @MainActor [weak self] in self?.restartListenerAfterDefunctFailure() }
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.publishFromNetworkQueue(.peerFound(String(describing: connection.endpoint)))
                self?.startConnection(connection)
            }
            listener.start(queue: listenerQueue)
        } catch {
            publish(.failed(error.localizedDescription))
        }
    }

    nonisolated private func connect(to endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .recOnTCP)
        startConnection(connection)
    }

    nonisolated private func processBrowserResults(_ results: Set<NWBrowser.Result>) {
        let interfaceSummary = results
            .flatMap(\.interfaces)
            .map { "\($0.type):\($0.name)" }
            .joined(separator: ",")
        RECONDiagnostics.emit(
            "bonjour_results",
            detail: "count=\(results.count) interfaces=\(interfaceSummary.isEmpty ? "none" : interfaceSummary)"
        )

        guard let endpoint = results.first?.endpoint else {
            publishFromNetworkQueue(.searching)
            return
        }
        guard connection?.state != .ready && connection?.state != .preparing else { return }
        publishFromNetworkQueue(.peerFound(String(describing: endpoint)))
        connect(to: endpoint)
    }

    private func restartBrowserAfterDefunctFailure() {
        guard activeRole == .monitor else { return }
        startBrowsing()
    }

    private func restartListenerAfterDefunctFailure() {
        guard activeRole == .camera else { return }
        startListening()
    }

    nonisolated private static func isDefunctDNSConnection(_ error: NWError) -> Bool {
        guard case let .dns(code) = error else { return false }
        return code == kDNSServiceErr_DefunctConnection
    }

    nonisolated private func startConnection(_ newConnection: NWConnection) {
        connection?.cancel()
        connection = newConnection
        publishFromNetworkQueue(.connecting)

        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            guard let self, let newConnection else { return }
            switch state {
            case .ready:
                self.publishFromNetworkQueue(.ready)
                self.receiveNext(on: newConnection)
            case let .waiting(error):
                self.publishFromNetworkQueue(.waiting(error.localizedDescription))
            case let .failed(error):
                self.publishFromNetworkQueue(.failed(error.localizedDescription))
            case .cancelled:
                self.publishFromNetworkQueue(.cancelled)
            default:
                break
            }
        }
        newConnection.start(queue: connectionQueue)
    }

    nonisolated private func receiveNext(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, context, _, error in
            guard let self, let connection else { return }

            if let data,
               let metadata = context?.protocolMetadata(definition: TLVFramingProtocol.definition) as? NWProtocolFramer.Message,
               let kind = metadata.reconMessageKind {
                self.onMessage?(ReceivedPeerMessage(kind: kind, data: data))
            }

            if let error {
                self.publishFromNetworkQueue(.failed(error.localizedDescription))
            } else {
                self.receiveNext(on: connection)
            }
        }
    }

    private func publish(_ newState: PeerTransportState) {
        RECONDiagnostics.emit("transport_state", detail: "value=\(String(describing: newState))")
        state = newState
        onStateChange?(newState)
    }

    nonisolated private func publishFromNetworkQueue(_ newState: PeerTransportState) {
        Task { @MainActor [weak self] in
            self?.publish(newState)
        }
    }
}

private enum TransportError: LocalizedError {
    case notConnected

    var errorDescription: String? { "Peer connection is not ready" }
}
