import Foundation

protocol CameraStateControlling: Sendable {
    func handle(_ request: CommandRequest) async -> CameraStateEvent
}

final class MockCameraStateController: CameraStateControlling {
    private var actualState: RecordingState = .stby

    func handle(_ request: CommandRequest) async -> CameraStateEvent {
        try? await Task.sleep(for: .milliseconds(350))

        switch request.commandType {
        case .startRecording:
            actualState = .recording
        case .stopRecording:
            actualState = .stby
        }

        return CameraStateEvent(
            relatedCommandID: request.commandID,
            recordingState: actualState,
            result: .confirmed,
            cameraTimestamp: .now,
            failureReason: nil
        )
    }
}
