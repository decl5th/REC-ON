import Foundation

enum MessageKind: UInt32, Codable, Sendable {
    case videoParameterSet = 1
    case videoFrame = 2
    case commandRequest = 16
    case cameraStateEvent = 17
}

enum CommandType: String, Codable, Sendable {
    case startRecording
    case stopRecording
}

struct CommandRequest: Codable, Equatable, Sendable {
    let commandID: UUID
    let commandType: CommandType
    let sentAt: Date
}

enum CommandResult: String, Codable, Sendable {
    case confirmed
    case failed
}

struct CameraStateEvent: Codable, Equatable, Sendable {
    let relatedCommandID: UUID
    let recordingState: RecordingState
    let result: CommandResult
    let cameraTimestamp: Date
    let failureReason: String?
}
