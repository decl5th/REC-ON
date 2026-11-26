@preconcurrency import AVFoundation
import SwiftUI
import UIKit

nonisolated final class RemoteVideoRenderer: @unchecked Sendable {
    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private var pendingSampleBuffer: CMSampleBuffer?

    @MainActor
    func attach(_ layer: AVSampleBufferDisplayLayer) {
        displayLayer = layer
        if let pendingSampleBuffer {
            enqueueOnMain(pendingSampleBuffer)
            self.pendingSampleBuffer = nil
        }
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        Task { @MainActor [weak self] in
            self?.enqueueOnMain(sampleBuffer)
        }
    }

    @MainActor
    private func enqueueOnMain(_ sampleBuffer: CMSampleBuffer) {
        guard let displayLayer else {
            pendingSampleBuffer = sampleBuffer
            return
        }

        if displayLayer.sampleBufferRenderer.status == .failed {
            displayLayer.sampleBufferRenderer.flush()
        }
        displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)
    }
}

struct RemoteVideoView: UIViewRepresentable {
    let renderer: RemoteVideoRenderer

    func makeUIView(context: Context) -> RemoteVideoSurfaceView {
        let view = RemoteVideoSurfaceView()
        renderer.attach(view.displayLayer)
        return view
    }

    func updateUIView(_ uiView: RemoteVideoSurfaceView, context: Context) {
        renderer.attach(uiView.displayLayer)
    }
}

final class RemoteVideoSurfaceView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        displayLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
