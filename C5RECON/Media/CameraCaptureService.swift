@preconcurrency import AVFoundation
import Combine
import Foundation

enum CameraCaptureStatus: Equatable {
    case idle
    case requestingPermission
    case configuring
    case running
    case failed(String)
}

@MainActor
final class CameraCaptureService: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var status: CameraCaptureStatus = .idle
    @Published private(set) var deliveredFrameCount = 0

    var onFirstFrame: (() -> Void)?

    nonisolated(unsafe) private var frameConsumer: (@Sendable (CMSampleBuffer) -> Void)?
    nonisolated(unsafe) private var hasDeliveredFirstFrame = false

    private let sessionQueue = DispatchQueue(label: "recon.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "recon.camera.frames")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()

        case .notDetermined:
            status = .requestingPermission
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.configureAndStart()
                    } else {
                        self.status = .failed("카메라 권한이 필요합니다")
                    }
                }
            }

        case .denied, .restricted:
            status = .failed("설정에서 카메라 권한을 허용해야 합니다")

        @unknown default:
            status = .failed("알 수 없는 카메라 권한 상태입니다")
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
        status = .idle
    }

    func setFrameConsumer(_ consumer: (@Sendable (CMSampleBuffer) -> Void)?) {
        frameConsumer = consumer
    }

    private func configureAndStart() {
        status = .configuring

        sessionQueue.async { [weak self] in
            guard let self else { return }

            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }

                if !self.session.isRunning {
                    self.session.startRunning()
                }

                Task { @MainActor in
                    self.status = .running
                }
            } catch {
                Task { @MainActor in
                    self.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    private nonisolated func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw CaptureError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CaptureError.cannotAddInput
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw CaptureError.cannotAddOutput
        }
        session.addOutput(videoOutput)
    }
}

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameConsumer?(sampleBuffer)

        let isFirstFrame = !hasDeliveredFirstFrame
        if isFirstFrame {
            hasDeliveredFirstFrame = true
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            deliveredFrameCount += 1
            if isFirstFrame {
                onFirstFrame?()
            }
        }
    }
}

private enum CaptureError: LocalizedError {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: "Camera 기기를 찾을 수 없습니다"
        case .cannotAddInput: "Camera input을 capture session에 추가할 수 없습니다"
        case .cannotAddOutput: "Video data output을 capture session에 추가할 수 없습니다"
        }
    }
}
