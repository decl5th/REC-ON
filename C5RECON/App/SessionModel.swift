import Combine
import Foundation

@MainActor
final class SessionModel: ObservableObject {
    @Published private(set) var state = SessionState()

    let cameraCapture: CameraCaptureService
    let videoPipeline: VideoPipelineService

    private let cameraStateController: any CameraStateControlling
    private let peerTransport: PeerTransport
    private let encodedFrameCounter = DiagnosticCounter()
    private let receivedFrameCounter = DiagnosticCounter()
    private var diagnosticScenarioTask: Task<Void, Never>?

    init(
        cameraStateController: (any CameraStateControlling)? = nil,
        peerTransport: PeerTransport? = nil
    ) {
        self.cameraStateController = cameraStateController ?? MockCameraStateController()
        self.peerTransport = peerTransport ?? PeerTransport()
        cameraCapture = CameraCaptureService()
        videoPipeline = VideoPipelineService()

        configureCallbacks()

        #if DEBUG
        if let scenario = Self.diagnosticScenario() {
            runDiagnosticScenario(scenario)
        } else if let role = Self.diagnosticLaunchRole() {
            RECONDiagnostics.emit("diagnostic_auto_role", detail: "role=\(role.rawValue)")
            send(.selectRole(role))
        } else {
            RECONDiagnostics.emit("app_ready", detail: "role=manual")
        }
        #endif
    }

    private func configureCallbacks() {
        cameraCapture.onFirstFrame = { [weak self] in
            guard let self, self.state.role == .camera else { return }
            RECONDiagnostics.emit("capture_first_frame")
            self.send(.mediaStreaming)
        }
        cameraCapture.setFrameConsumer { [videoPipeline] sampleBuffer in
            videoPipeline.encode(sampleBuffer)
        }
        videoPipeline.onEncodedFrame = { [weak self] data in
            guard let self else { return }
            let count = self.encodedFrameCounter.increment()
            if count == 1 || count.isMultiple(of: 300) {
                RECONDiagnostics.emit("encoded_frame", detail: "count=\(count) bytes=\(data.count)")
            }
            Task { @MainActor [weak sessionModel = self] in
                guard let sessionModel, sessionModel.state.role == .camera else { return }
                try? await sessionModel.peerTransport.send(data, kind: .videoFrame)
            }
        }
        videoPipeline.onFirstDecodedFrame = { [weak self] in
            RECONDiagnostics.emit("decoded_first_frame")
            Task { @MainActor [weak sessionModel = self] in
                guard let sessionModel, sessionModel.state.role == .monitor else { return }
                sessionModel.send(.mediaStreaming)
            }
        }
        self.peerTransport.onStateChange = { [weak self] transportState in
            self?.handleTransportState(transportState)
        }
        self.peerTransport.onMessage = { [weak self] message in
            guard let self else { return }
            if message.kind == .videoFrame {
                let count = self.receivedFrameCounter.increment()
                if count == 1 || count.isMultiple(of: 300) {
                    RECONDiagnostics.emit("received_video_frame", detail: "count=\(count) bytes=\(message.data.count)")
                }
                self.videoPipeline.decode(message.data)
            } else {
                Task { @MainActor in
                    self.handlePeerMessage(message)
                }
            }
        }
    }

    func send(_ action: SessionAction) {
        switch action {
        case let .selectRole(role):
            state.role = role
            state.connectionIssue = nil
            state.discoveredPeerName = nil
            state.connectionPhase = .idle
            appendLog("role selected: \(role.rawValue)")
            if role == .camera {
                send(.mediaPreparing)
                cameraCapture.start()
            } else {
                send(.mediaPreparing)
            }
            send(.peerConnecting)
            peerTransport.start(for: role)
            scheduleConnectionGuidance(for: role)
            scheduleDiagnosticCheckpoints(for: role)

        case .leaveRole:
            diagnosticScenarioTask?.cancel()
            cameraCapture.stop()
            peerTransport.cancel()
            state = SessionState()

        case .peerConnecting:
            state.peerConnection = .connecting
            appendLog("peer: connecting")

        case .peerConnected:
            state.peerConnection = .connected
            state.connectionPhase = .connected
            state.connectionDetail = "Camera와 Monitor가 직접 연결되었습니다"
            state.connectionIssue = nil
            state.freshness = .current
            appendLog("peer: connected")

        case .peerDisconnected:
            state.peerConnection = .disconnected
            state.mediaStream = .unavailable
            state.freshness = .stale
            appendLog("peer: disconnected; actual state is stale")

        case .retryConnection:
            guard let role = state.role else { return }
            state.connectionIssue = nil
            state.discoveredPeerName = nil
            send(.peerConnecting)
            peerTransport.start(for: role)
            scheduleConnectionGuidance(for: role)
            scheduleDiagnosticCheckpoints(for: role)

        case .mediaPreparing:
            state.mediaStream = .preparing
            appendLog("media: preparing")

        case .mediaStreaming:
            state.mediaStream = .streaming
            appendLog("media: first frame rendered")

        case .mediaStalled:
            state.mediaStream = .stalled
            appendLog("media: stalled")

        case let .recordingRequested(type):
            guard state.canSendRecordingCommand else { return }

            let request = CommandRequest(commandID: UUID(), commandType: type, sentAt: .now)
            state.command = .requested(commandID: request.commandID)
            appendLog("command requested: \(type.rawValue) [\(request.commandID)]")

            Task {
                if state.role == .camera {
                    send(.commandAccepted(request.commandID))
                    let cameraEvent = await cameraStateController.handle(request)
                    send(.cameraStateReceived(cameraEvent))
                    await sendCameraEvent(cameraEvent)
                } else {
                    do {
                        let data = try JSONEncoder().encode(request)
                        try await peerTransport.send(data, kind: .commandRequest)
                        send(.commandAccepted(request.commandID))
                    } catch {
                        send(.commandFailed(commandID: request.commandID, reason: error.localizedDescription))
                    }
                }
            }

        case let .commandAccepted(commandID):
            state.command = .pending(commandID: commandID)
            appendLog("command sent; waiting for Camera event: \(commandID)")

        case let .cameraStateReceived(event):
            guard event.result == .confirmed else {
                send(.commandFailed(
                    commandID: event.relatedCommandID,
                    reason: event.failureReason ?? "Camera rejected the request"
                ))
                return
            }

            // Only a Camera-origin event changes actual recording state.
            state.actualRecording = event.recordingState
            state.freshness = .current
            state.lastCameraTimestamp = event.cameraTimestamp
            state.command = .confirmed(commandID: event.relatedCommandID)
            appendLog("camera confirmed: \(event.recordingState.rawValue)")

            Task {
                try? await Task.sleep(for: .milliseconds(500))
                send(.clearCommandFeedback)
            }

        case let .commandFailed(commandID, reason):
            state.command = .failed(commandID: commandID, reason: reason)
            appendLog("command failed: \(reason)")

        case .clearCommandFeedback:
            state.command = .idle
        }
    }

    private func appendLog(_ message: String) {
        let timestamp = Date.now.formatted(date: .omitted, time: .standard)
        state.eventLog.append("\(timestamp)  \(message)")
    }

    private func handleTransportState(_ transportState: PeerTransportState) {
        switch transportState {
        case .idle:
            break
        case .searching:
            state.connectionPhase = .searching
            state.connectionDetail = "같은 Wi-Fi에서 Camera를 자동 검색 중입니다"
            if state.role != nil { send(.peerConnecting) }
        case .listening:
            state.connectionPhase = .advertising
            state.connectionDetail = "Camera 연결을 열었습니다 · Monitor 실행을 기다리는 중"
            if state.role != nil { send(.peerConnecting) }
        case let .peerFound(name):
            state.connectionPhase = .peerFound
            state.discoveredPeerName = name
            state.connectionDetail = "상대 기기를 발견했습니다 · TCP 연결을 준비하는 중"
            appendLog("peer discovered: \(name)")
        case .connecting:
            state.connectionPhase = .connecting
            state.connectionDetail = "상대 기기를 찾았습니다 · 연결을 설정하는 중"
            if state.role != nil { send(.peerConnecting) }
        case .ready:
            send(.peerConnected)
        case let .waiting(reason):
            state.connectionPhase = .waiting
            state.peerConnection = .connecting
            state.connectionDetail = "네트워크 사용 허가 또는 경로를 기다리는 중"
            state.connectionIssue = "로컬 네트워크 권한과 Wi-Fi를 확인하세요 · \(reason)"
            appendLog("transport waiting: \(reason)")
        case let .failed(reason):
            state.connectionPhase = .failed
            state.connectionIssue = "연결 실패 · \(reason)"
            appendLog("transport failed: \(reason)")
            send(.peerDisconnected)
        case .cancelled:
            if state.role != nil { send(.peerDisconnected) }
        }
    }

    func resumeTransportAfterForegroundTransition() {
        guard state.role != nil else { return }
        #if DEBUG
        guard Self.diagnosticScenario() == nil else { return }
        #endif
        peerTransport.refreshAfterForegroundTransition()
    }

    private func scheduleConnectionGuidance(for role: DeviceRole) {
        Task {
            try? await Task.sleep(for: .seconds(12))
            guard state.role == role, state.peerConnection == .connecting else { return }
            state.connectionIssue = role == .camera
                ? "Monitor 기기에서 Monitor 역할을 선택했는지 확인하세요"
                : "Camera 기기에서 Camera 역할을 먼저 실행했는지 확인하세요"
            appendLog("peer discovery timeout guidance shown")
        }
    }

    private func scheduleDiagnosticCheckpoints(for role: DeviceRole) {
        Task {
            try? await Task.sleep(for: .seconds(15))
            guard state.role == role else { return }
            let connectionPassed = state.peerConnection == .connected
            RECONDiagnostics.emit(
                connectionPassed ? "checkpoint_connection_pass" : "checkpoint_connection_fail",
                detail: "role=\(role.rawValue) detail=\(state.connectionDetail) peer=\(state.discoveredPeerName ?? "none")"
            )

            try? await Task.sleep(for: .seconds(15))
            guard state.role == role else { return }
            let mediaPassed = state.mediaStream == .streaming
            RECONDiagnostics.emit(
                mediaPassed ? "checkpoint_media_pass" : "checkpoint_media_fail",
                detail: "role=\(role.rawValue) state=\(String(describing: state.mediaStream))"
            )
        }
    }

    #if DEBUG
    private static func diagnosticLaunchRole() -> DeviceRole? {
        let arguments = ProcessInfo.processInfo.arguments
        if let value = arguments.first(where: { $0.hasPrefix("--recon-role=") })?.split(separator: "=").last {
            return DeviceRole(rawValue: String(value))
        }
        if let index = arguments.firstIndex(of: "--recon-role"), arguments.indices.contains(index + 1) {
            return DeviceRole(rawValue: arguments[index + 1])
        }
        return nil
    }


    private static func diagnosticScenario() -> String? {
        ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--recon-scenario=") })?
            .split(separator: "=")
            .last
            .map(String.init)
    }

    private func runDiagnosticScenario(_ scenario: String) {
        guard scenario == "connection-lifecycle" else {
            RECONDiagnostics.emit("scenario_fail", detail: "unknown=\(scenario)")
            return
        }

        state.role = .monitor
        state.mediaStream = .preparing
        RECONDiagnostics.emit("scenario_start", detail: "name=\(scenario)")
        diagnosticScenarioTask = Task { [weak self] in
            guard let self else { return }
            handleTransportState(.searching)
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            handleTransportState(.peerFound("simulated-camera.local"))
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            handleTransportState(.connecting)
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            handleTransportState(.ready)
            send(.mediaStreaming)

            let passed = state.connectionPhase == .connected
                && state.peerConnection == .connected
                && state.mediaStream == .streaming
                && state.discoveredPeerName == "simulated-camera.local"
            RECONDiagnostics.emit(
                passed ? "scenario_pass" : "scenario_fail",
                detail: "name=\(scenario) phase=\(String(describing: state.connectionPhase)) media=\(String(describing: state.mediaStream))"
            )
        }
    }
    #endif

    private func handlePeerMessage(_ message: ReceivedPeerMessage) {
        switch message.kind {
        case .videoFrame, .videoParameterSet:
            break
        case .commandRequest:
            guard state.role == .camera,
                  let request = try? JSONDecoder().decode(CommandRequest.self, from: message.data) else {
                return
            }
            appendLog("remote command received: \(request.commandType.rawValue)")
            Task {
                let cameraEvent = await cameraStateController.handle(request)
                send(.cameraStateReceived(cameraEvent))
                await sendCameraEvent(cameraEvent)
            }
        case .cameraStateEvent:
            guard state.role == .monitor,
                  let event = try? JSONDecoder().decode(CameraStateEvent.self, from: message.data) else {
                return
            }
            send(.cameraStateReceived(event))
        }
    }

    private func sendCameraEvent(_ event: CameraStateEvent) async {
        do {
            let data = try JSONEncoder().encode(event)
            try await peerTransport.send(data, kind: .cameraStateEvent)
        } catch {
            appendLog("camera state send failed: \(error.localizedDescription)")
        }
    }
}
