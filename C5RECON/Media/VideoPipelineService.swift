@preconcurrency import CoreMedia
import Foundation
@preconcurrency import Transcoding

nonisolated final class VideoPipelineService: @unchecked Sendable {
    let remoteRenderer = RemoteVideoRenderer()

    var onEncodedFrame: (@Sendable (Data) -> Void)?
    var onFirstDecodedFrame: (@Sendable () -> Void)?

    private let encoder: VideoEncoder
    private let encoderAdaptor: VideoEncoderAnnexBAdaptor
    private let decoder: VideoDecoder
    private let decoderAdaptor: VideoDecoderAnnexBAdaptor

    private var encodedFrameTask: Task<Void, Never>?
    private var decodedFrameTask: Task<Void, Never>?
    private let firstFrameLock = NSLock()
    private var didDecodeFirstFrame = false

    init() {
        var encoderConfig = VideoEncoder.Config.ultraLowLatency
        encoderConfig.expectedFrameRate = 30
        encoderConfig.averageBitRate = 3_000_000
        encoderConfig.maxKeyFrameInterval = 30
        encoderConfig.allowFrameReordering = false

        let encoder = VideoEncoder(config: encoderConfig)
        let decoder = VideoDecoder(config: .init(realTime: true))
        self.encoder = encoder
        self.decoder = decoder
        encoderAdaptor = VideoEncoderAnnexBAdaptor(videoEncoder: encoder)
        decoderAdaptor = VideoDecoderAnnexBAdaptor(videoDecoder: decoder, codec: .hevc)

        encodedFrameTask = Task { [weak self, encoderAdaptor] in
            for await data in encoderAdaptor.annexBData {
                guard let self, !Task.isCancelled else { return }
                onEncodedFrame?(data)
            }
        }

        decodedFrameTask = Task { [weak self, decoder] in
            for await sampleBuffer in decoder.decodedSampleBuffers {
                guard let self, !Task.isCancelled else { return }
                remoteRenderer.enqueue(sampleBuffer)

                firstFrameLock.lock()
                let isFirstFrame = !didDecodeFirstFrame
                didDecodeFirstFrame = true
                firstFrameLock.unlock()

                if isFirstFrame {
                    onFirstDecodedFrame?()
                }
            }
        }
    }

    deinit {
        encodedFrameTask?.cancel()
        decodedFrameTask?.cancel()
    }

    func encode(_ sampleBuffer: CMSampleBuffer) {
        encoder.encode(sampleBuffer)
    }

    func decode(_ annexBData: Data) {
        decoderAdaptor.decode(annexBData)
    }
}
