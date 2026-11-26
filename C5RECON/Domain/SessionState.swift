import Foundation

enum DeviceRole: String, CaseIterable, Identifiable, Sendable {
    case camera
    case monitor

    var id: Self { self }

    var title: String {
        switch self {
        case .camera: "Camera"
        case .monitor: "Monitor"
        }
    }

    var subtitle: String {
        switch self {
        case .camera: "영상을 촬영하고 상태를 전송합니다"
        case .monitor: "영상을 확인하고 녹화를 요청합니다"
        }
    }
}

enum PeerConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case disconnected
}

enum ConnectionPhase: Equatable, Sendable {
    case idle
    case searching
    case advertising
    case peerFound
    case connecting
    case connected
    case waiting
    case failed
}

enum MediaStreamState: Equatable, Sendable {
    case unavailable
    case preparing
    case streaming
    case stalled
}

enum RecordingState: String, Codable, Equatable, Sendable {
    case stby
    case recording
}

enum StateFreshness: Equatable, Sendable {
    case unknown
    case current
    case stale
}

enum CommandLifecycle: Equatable, Sendable {
    case idle
    case requested(commandID: UUID)
    case pending(commandID: UUID)
    case confirmed(commandID: UUID)
    case failed(commandID: UUID, reason: String)
}

struct SessionState: Equatable, Sendable {
    var role: DeviceRole?
    var peerConnection: PeerConnectionState = .idle
    var connectionPhase: ConnectionPhase = .idle
    var connectionDetail = "역할을 선택해 연결을 시작하세요"
    var connectionIssue: String?
    var discoveredPeerName: String?
    var mediaStream: MediaStreamState = .unavailable
    var actualRecording: RecordingState = .stby
    var freshness: StateFreshness = .unknown
    var command: CommandLifecycle = .idle
    var lastCameraTimestamp: Date?
    var eventLog: [String] = []

    var canSendRecordingCommand: Bool {
        peerConnection == .connected && freshness == .current && command == .idle
    }
}
