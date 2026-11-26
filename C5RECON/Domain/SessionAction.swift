import Foundation

enum SessionAction: Sendable {
    case selectRole(DeviceRole)
    case leaveRole
    case peerConnecting
    case peerConnected
    case peerDisconnected
    case retryConnection
    case mediaPreparing
    case mediaStreaming
    case mediaStalled
    case recordingRequested(CommandType)
    case commandAccepted(UUID)
    case cameraStateReceived(CameraStateEvent)
    case commandFailed(commandID: UUID, reason: String)
    case clearCommandFeedback
}
