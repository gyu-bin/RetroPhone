# OldOS 분석 및 재사용 판단

분석 대상: https://github.com/zzanehip/The-OldOS-Project — `master` 최신 커밋
`7792e45` (2026-11-01, "2.0 (9) clock, calculator, homescreen"), 배포 버전 2.0 (minOS 16.0).

## 라이선스
| 대상 | 상태 | 판단 |
|---|---|---|
| 소스 코드 | README에 **CC BY 4.0** 명시 (별도 LICENSE 파일 없음) | 출처 표시 조건으로 재사용 가능 |
| 이미지 에셋 (`Assets.xcassets`: 아이콘, 배경화면, UIKit 크롬, 잠금화면 슬라이더 등) | iOS 4 원본 그래픽을 재현/추출한 것으로 보이며 원 저작권은 Apple에 있음. OldOS 작성자가 CC BY로 재라이선스할 권한이 없음 | **사용하지 않음** → 전부 코드로 새로 그림 |
| 사운드 (`Tones/unlock.aiff`, `dtmf-*.caf`, `ClockSounds/*.caf`) | iOS 원본 시스템 사운드 | **사용하지 않음** → 런타임 합성 (`SoundService`) |
| 폰트 (`Fonts/`) | 개별 라이선스 불명확 | 사용하지 않음 (시스템 Helvetica / Marker Felt 사용) |
| 서드파티 패키지 (Alamofire, SwiftyJSON, SDWebImageSwiftUI, SwiftUIPager, mailcore2, XCDYouTubeKit, OAuth2, FeedKit 등 12개) | 각자 라이선스 | 불필요 — RetroPhone은 외부 패키지 0개 |

## 기존 구조 (요약)
- 약 3.7만 줄 SwiftUI. 앱별 단일 대형 파일 (`iPod.swift` 2.9k줄, `Youtube.swift` 3.5k줄, `Common.swift` 2.8k줄).
- 문자열 기반 화면 전환(`current_view = "HS"`), 전역 `UserDefaults` 키, 싱글톤 혼재.
- 거의 모든 화면이 PNG 에셋(`Image("…")`)에 의존 → 에셋을 빼면 UI가 성립하지 않음.
- 상태바에 `CTTelephonyNetworkInfo` 통신사명 사용(iOS 16.4+에서는 실제 값이 아닌 고정 문자열 반환) → 요구사항(허위 표시 금지)과 충돌.
- 날씨는 외부 API 키 기반, YouTube/Mail/App Store/iTunes 등 2010년 서비스 재현 앱은 본 프로젝트 범위 밖.

## 결론
OldOS를 포크하면 (1) Apple 에셋 제거 시 대부분의 화면을 다시 그려야 하고 (2) 단일 파일 구조를 §15의
모듈 구조로 바꾸는 비용이 신규 작성보다 크다고 판단했습니다. 따라서:

- **참고한 것**: 잠금화면 상·하단 패널 구성, 잠금 해제 시 아이콘이 확대 상태에서 날아 들어오는 연출
  (`apps_scale = 4` → 1), 폴더 패널 방식, 상태바 갱신 방식(분 단위 타이머 + 배터리 알림)의 아이디어.
- **새로 작성한 것**: 전체 코드(모듈 구조, 레이아웃 엔진, 위젯, 앱), 모든 아이콘/배경화면(벡터 드로잉),
  모든 효과음(합성).
- **출처 표시**: 설정 › 정보 › 라이선스 및 오픈소스 출처에 OldOS (CC BY 4.0, © Zane Kleinberg) 표기.

OldOS 원본 빌드(최신 Xcode에서의 컴파일 및 기능 동작 확인)는 수행하지 않았습니다 — 위 결론에 따라 코드를
가져오지 않았기 때문이며, 필요하면 별도로 확인할 수 있습니다.
