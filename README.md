# REC:ON

REC:ON은 같은 Wi-Fi에 있는 두 iOS 기기를 `Camera`와 `Monitor`로 나눠, Camera 영상을 Monitor에서 보고 녹화 시작·정지를 요청하는 학습용 프로토타입이다.

## 현재 구현 범위

- iOS 26.0, SwiftUI
- `MV + Session State Machine + Services`
- Camera: AVFoundation 720p capture와 local preview
- Media: HEVC ultra-low-latency encode/decode (`Transcoding` 0.0.2)
- Network: Bonjour `_c5recon._tcp` discovery, TCP, 8-byte TLV framing
- Monitor: `AVSampleBufferDisplayLayer` remote preview
- Control: Start/Stop request와 Camera-origin state event 왕복

실제·mock·미구현 경계:

- 실제: 카메라 캡처, HEVC codec, Bonjour/TCP 연결, TLV 메시지, 원격 렌더
- mock: Camera의 녹화 적용 결과. 약 180ms 뒤 `CameraStateEvent`를 생성한다.
- 미구현: AVFoundation 파일 녹화, 재연결, adaptive bitrate, 명령 중복 제거, production pairing, 전체 hi-fi 상태

`REC`/`STBY` actual state는 Monitor 요청만으로 바뀌지 않는다. Camera가 생성해 전송한 `CameraStateEvent`만 actual state를 바꾼다.

## 실행

1. [C5RECON.xcodeproj](C5RECON.xcodeproj)을 Xcode에서 열고, 실기기 설치 시 Signing & Capabilities에서 자신의 개발 팀을 선택한다.
2. 같은 Wi-Fi에 연결된 iOS 26.0 이상 기기 두 대에 동일 앱을 설치한다.
3. 한 기기에서 `Camera`, 다른 기기에서 `Monitor`를 선택한다.
4. Camera에서 카메라 및 로컬 네트워크 권한을 허용한다.
5. 양쪽 연결 표시가 `연결됨 · Bonjour/TCP`가 되는지 확인한다.
6. Monitor 영상이 10초 이상 유지되는지 확인한다.
7. Monitor에서 Start와 Stop을 각각 눌러 `요청 전달 중 → Camera 처리 중 → Camera 확인 완료`와 actual `REC/STBY` 전환을 확인한다.

연결은 별도 페어링 코드 없이 Bonjour로 자동 진행된다. Camera 기기에서 `Camera` 역할을 먼저 선택해 연결을 열어 둔 뒤, 다른 기기에서 `Monitor`를 선택한다. 두 기기 모두 `설정 → 개인정보 보호 및 보안 → 로컬 네트워크 → C5RECON`이 활성화되어야 한다.

두 기기는 서로 다른 기기여야 한다. 첫 로컬 네트워크 권한 승인 직후 발견이 지연되면 두 앱을 완전히 종료한 뒤 Camera를 먼저, Monitor를 다음에 다시 실행한다.

계속 검색 중이면 두 기기의 Wi-Fi SSID가 정확히 같은지 확인하고 VPN을 끈다. Guest·회사·학교 Wi-Fi는 기기 간 통신이나 Bonjour/mDNS를 차단할 수 있으므로 일반 공유기 네트워크에서 다시 확인한다. 새 연결 안내 화면의 `설정 열기`, `다시 시도`와 12초 진단 문구를 사용한다.

## 빌드 검증

```sh
xcodebuild \
  -project C5RECON.xcodeproj \
  -scheme C5RECON \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/C5RECONDerived \
  CODE_SIGNING_ALLOWED=NO build
```

2026-08-26 기준 위 generic iOS 26.0 unsigned build는 성공했다. signed install과 two-device runtime은 실제 기기에서 별도 확인해야 한다.

## 코드 지도

- 앱 상태와 action 처리: `C5RECON/App/SessionModel.swift`
- 세션 상태: `C5RECON/Domain/SessionState.swift`
- 명령/state 계약: `C5RECON/Domain/Messages.swift`
- 캡처: `C5RECON/Media/CameraCaptureService.swift`
- HEVC encode/decode: `C5RECON/Media/VideoPipelineService.swift`
- 원격 렌더: `C5RECON/Media/RemoteVideoRenderer.swift`
- discovery/transport: `C5RECON/Network/PeerTransport.swift`
- TLV framing: `C5RECON/Network/TLVFramingProtocol.swift`

Media frame은 `SessionModel`을 통과하지 않는다. Camera frame은 `CameraCaptureService → VideoPipelineService → PeerTransport`로 전송되고, 수신 frame은 `PeerTransport → VideoPipelineService → RemoteVideoRenderer`로 간다. 명령과 Camera state만 `SessionModel`을 거친다.

## 참고 프로젝트

- [LocalVideoStreaming](https://github.com/finnvoor/LocalVideoStreaming) · 미디어 전송 구조 참고
- [Transcoding](https://github.com/finnvoor/Transcoding) · HEVC 인코딩·디코딩 의존성
