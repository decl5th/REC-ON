# REC:ON | 두 기기로 쓰는 원격 뷰파인더

혼자 촬영할 때, 카메라를 세워 둔 자리로 돌아가지 않고도 구도를 확인할 수 있을까요? REC:ON은 같은 Wi-Fi에 연결한 두 대의 iPhone 또는 iPad를 **촬영용 카메라(Camera)**와 **손에 들고 보는 모니터(Monitor)**로 나눠 쓰는 학습용 프로토타입입니다.

| 주요 기능 | Camera · 촬영하는 기기 | Monitor · 확인하는 기기 |
| --- | --- | --- |
| 영상 미리보기 | 카메라 영상을 720p로 캡처해 화면에 표시하고 전송합니다. | 받은 영상을 복호화해 원격 화면에 표시합니다. |
| 자동 연결 | 같은 네트워크에 자신을 알리고 접속을 기다립니다. | Camera를 자동으로 찾아 연결합니다. 서버 주소나 페어링 코드는 필요 없습니다. |
| 녹화 제어 실험 | 시작·정지 요청을 처리하고 모의 녹화 상태를 돌려줍니다. | 요청을 보낸 뒤 Camera의 응답을 받아 대기(`STBY`) 또는 녹화(`REC`)를 표시합니다. |

**현재 한계:** `REC`는 녹화 상태를 주고받는 실험용 표시이며, 동영상 파일은 저장되지 않습니다. 시뮬레이터 두 대에서는 기기 검색과 TCP 연결을 확인했습니다. 실기기 테스트에서는 Camera 검색에 성공하지 못했으며, 실기기 간 영상 수신과 연속 재생은 아직 검증되지 않았습니다.

## 같은 Wi-Fi에서 두 기기로 실행하기

**준비물:** Xcode가 설치된 Mac, iOS 또는 iPadOS 26.0 이상 실기기 두 대, 기기 간 통신이 가능한 Wi-Fi.

1. **두 기기에 설치합니다.** 저장소를 내려받아 [C5RECON.xcodeproj](C5RECON.xcodeproj)를 Xcode에서 엽니다. `C5RECON` 타깃의 **Signing & Capabilities → Team**에서 자신의 개발 팀을 선택합니다. 앱 식별자 등록 오류가 나면 **Bundle Identifier**를 고유한 값으로 바꿉니다. 실행 대상에서 각 기기를 차례로 선택해 **Run**으로 같은 앱을 설치합니다.
2. **Camera를 먼저 엽니다.** 두 기기를 같은 Wi-Fi에 연결합니다. 촬영할 기기에서 **Camera**를 선택하고, 카메라와 로컬 네트워크 접근을 허용합니다. `Camera 광고 중`은 다른 기기가 찾을 수 있도록 접속을 기다린다는 뜻입니다. 이 화면을 유지하세요.
3. **다른 기기에서 Monitor를 엽니다.** **Monitor**를 선택하고 로컬 네트워크 접근을 허용합니다. 별도 입력 없이 Camera를 검색합니다. 양쪽에 `연결됨 · Bonjour/TCP`가 뜨면 두 기기 사이의 연결이 열린 것입니다.
4. **영상과 제어를 따로 확인합니다.** Camera 앞에서 손을 움직여 Monitor에도 움직임이 보이는지 확인합니다. 이어 Monitor의 **빨간 원**을 누르면 시작 요청, **빨간 사각형**을 누르면 정지 요청입니다. 버튼을 누른 순간이 아니라 `Camera 확인 완료` 응답을 받았을 때 상태가 `REC` 또는 `STBY`로 바뀌는지 확인하세요.

### 연결이 안 될 때

- **Monitor에 `0대 · Camera 광고를 기다리는 중`이 계속 보이면:** 두 기기의 Wi-Fi 이름이 같은지, Camera 화면이 열려 있는지 확인하세요. 양쪽 **설정 → 개인정보 보호 및 보안 → 로컬 네트워크**에서 앱을 허용한 뒤 Monitor의 **다시 시도**를 누르세요. 게스트 Wi-Fi는 같은 이름이어도 기기 간 통신을 차단할 수 있습니다.
- **연결됐는데 영상이 안 보이면:** 연결 성공은 영상 수신 성공과 다릅니다. Camera의 로컬 미리보기가 먼저 보이는지 확인하세요. 보이지 않으면 Camera 기기의 카메라 권한을, 보인다면 Monitor의 원격 영상 수신을 따로 점검하세요.

<details>
<summary>개발 참고: 영상 경로와 빌드 확인</summary>

영상은 Camera에서 [캡처](C5RECON/Media/CameraCaptureService.swift) → [HEVC 인코딩](C5RECON/Media/VideoPipelineService.swift) → [TCP 전송](C5RECON/Network/PeerTransport.swift)을 거쳐 Monitor에서 복호화·[표시](C5RECON/Media/RemoteVideoRenderer.swift)됩니다. 녹화 요청과 응답은 영상과 별도로 [세션 모델](C5RECON/App/SessionModel.swift)에서 처리합니다. [Camera 제어 구현](C5RECON/Control/CameraStateControlling.swift)에서 모의 녹화 동작을 확인할 수 있습니다.

서명 없이 빌드만 확인하려면 저장소 최상위 폴더에서 실행하세요. 이 명령은 실기기에 앱을 설치하지 않습니다.

```sh
xcodebuild -project C5RECON.xcodeproj -scheme C5RECON -configuration Debug \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

참고 프로젝트: [LocalVideoStreaming](https://github.com/finnvoor/LocalVideoStreaming) · HEVC 의존성: [Transcoding](https://github.com/finnvoor/Transcoding)

</details>
