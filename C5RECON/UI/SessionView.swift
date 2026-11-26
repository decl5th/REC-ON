import SwiftUI
import UIKit

struct SessionView: View {
    @ObservedObject var session: SessionModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(red: 0.05, green: 0.07, blue: 0.09)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if session.state.peerConnection != .connected {
                    connectionGuide
                }
                preview
                controlRail
            }
        }
    }

    private var connectionGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: session.state.connectionIssue == nil
                    ? "antenna.radiowaves.left.and.right"
                    : "exclamationmark.triangle.fill")
                    .foregroundStyle(session.state.connectionIssue == nil ? .cyan : .yellow)

                VStack(alignment: .leading, spacing: 5) {
                    Text(session.state.connectionDetail)
                        .font(.headline)
                    Text(roleConnectionInstruction)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let issue = session.state.connectionIssue {
                        Text(issue)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.yellow)
                    }
                }

                Spacer()

                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.bordered)

                Button("다시 시도") {
                    session.send(.retryConnection)
                }
                .buttonStyle(.borderedProminent)
            }

            Label(
                "두 기기 모두 설정 → 개인정보 보호 및 보안 → 로컬 네트워크에서 C5RECON을 허용해야 합니다",
                systemImage: "wifi"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 18) {
                Label("Bonjour 검색", systemImage: "magnifyingglass")
                Text(discoveryResultText)
                    .font(.caption.monospaced())
                    .foregroundStyle(session.state.discoveredPeerName == nil ? Color.white.opacity(0.55) : Color.green)
                    .lineLimit(1)
                Spacer()
                Text("TCP · \(connectionText)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var roleConnectionInstruction: String {
        switch session.state.role {
        case .camera:
            "이 화면을 유지하고, 다른 기기에서 REC:ON을 열어 Monitor를 선택하세요."
        case .monitor:
            "다른 기기에서 Camera를 먼저 선택해 둔 상태여야 자동으로 발견됩니다."
        case nil:
            "한 기기는 Camera, 다른 기기는 Monitor 역할이어야 합니다."
        }
    }

    private var discoveryResultText: String {
        if let peerName = session.state.discoveredPeerName {
            return "발견됨 · \(peerName)"
        }
        return session.state.role == .monitor
            ? "0대 · Camera 광고를 기다리는 중"
            : "Monitor 접속 0대"
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(session.state.role?.title.uppercased() ?? "")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            connectionChip
            Spacer()

            Button("역할 변경") {
                session.send(.leaveRole)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var preview: some View {
        ZStack {
            Color(white: 0.08)

            if session.state.role == .camera {
                CameraPreviewView(session: session.cameraCapture.session)
            } else {
                RemoteVideoView(renderer: session.videoPipeline.remoteRenderer)
            }

            VStack {
                HStack {
                    actualStateBadge
                    Spacer()
                }
                Spacer()
            }
            .padding(18)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }

    private var controlRail: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(commandText)
                    .font(.headline)
                Text("Actual state는 Camera event로만 변경됩니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if session.state.actualRecording == .stby {
                Button {
                    session.send(.recordingRequested(.startRecording))
                } label: {
                    Circle()
                        .fill(.red)
                        .frame(width: 34, height: 34)
                        .padding(8)
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(!session.state.canSendRecordingCommand)
                .accessibilityLabel("녹화 시작 요청")
            } else {
                Button {
                    session.send(.recordingRequested(.stopRecording))
                } label: {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.red)
                        .frame(width: 27, height: 27)
                        .padding(12)
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(!session.state.canSendRecordingCommand)
                .accessibilityLabel("녹화 정지 요청")
            }
        }
        .padding(24)
    }

    private var connectionChip: some View {
        Text(connectionText)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.1), in: Capsule())
    }

    private var actualStateBadge: some View {
        HStack(spacing: 8) {
            if session.state.actualRecording == .recording {
                Circle().fill(.red).frame(width: 9, height: 9)
            }
            Text(session.state.actualRecording == .recording ? "REC" : "STBY")
                .font(.system(.headline, design: .monospaced, weight: .bold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.72), in: Capsule())
    }

    private var connectionText: String {
        switch session.state.connectionPhase {
        case .idle: "연결 전"
        case .searching: "Camera 검색 중 · 0대"
        case .advertising: "Camera 광고 중"
        case .peerFound: "Camera 발견"
        case .connecting: "TCP 연결 중"
        case .connected: "연결됨 · Bonjour/TCP"
        case .waiting: "네트워크 대기 중"
        case .failed: "연결 실패"
        }
    }

    private var commandText: String {
        switch session.state.command {
        case .idle: "명령 대기"
        case .requested: "요청 전달 중"
        case .pending: "Camera 처리 중"
        case .confirmed: "Camera 확인 완료"
        case let .failed(_, reason): "실패 · \(reason)"
        }
    }
}
