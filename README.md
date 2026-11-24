# RetroPhone

최신 아이폰에서 2010년 아이폰 4(iOS 4)의 사용 경험을 재현하는 네이티브 iOS 앱입니다.
실제 연락처·사진·캘린더·음악·위치·배터리 정보를 사용하며, 모든 아이콘·배경화면·효과음은
코드로 직접 그리거나 합성한 독자 제작물입니다.

> 앱 안의 **가상** 잠금화면/홈 화면입니다. 시스템 홈 화면이나 보안 기능을 바꾸지 않으며,
> 화면 하단에서 위로 쓸어 올리면 언제든 실제 iOS로 돌아갈 수 있습니다.

## 요구 사항
- Xcode 27 이상 (iOS 27 SDK), macOS 27
- 배포 대상 iOS 26.0+ (iOS 27 우선 검증), iPhone 전용 세로 화면
- 외부 패키지 없음

## 빌드
```bash
open RetroPhone.xcodeproj
```
1. 타깃 **RetroPhone › Signing & Capabilities**에서 Team을 본인 계정으로 지정하세요
   (무료 Apple ID 개인 팀도 가능). 필요하면 Bundle Identifier(`com.retrophone.RetroPhone`)를 고유하게 바꿉니다.
2. 실행 대상(시뮬레이터 또는 연결한 iPhone)을 고르고 ⌘R.

명령줄 빌드/테스트:
```bash
xcodebuild -project RetroPhone.xcodeproj -scheme RetroPhone -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
```bash
xcodebuild -project RetroPhone.xcodeproj -scheme RetroPhone -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```
(시뮬레이터 이름은 `xcrun simctl list devices available`로 확인하세요.)

## 실기기 설치 (개인용)
1. iPhone을 Mac에 연결하고 iPhone에서 **설정 › 개인정보 보호 및 보안 › 개발자 모드**를 켭니다.
2. Xcode에서 기기를 선택하고 ⌘R. 처음에는 iPhone **설정 › 일반 › VPN 및 기기 관리**에서 개발자 앱을 신뢰해야 합니다.
3. 무료 개인 팀으로 서명한 앱은 7일 후 다시 설치해야 합니다.

## UI 테스트용 실행 인자
`-resetState`(저장 데이터 초기화), `-skipSetup`(초기 설정 건너뜀), `-language ko|en`, `-uiTesting`.

## 프로젝트 구조
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 참고. Xcode의 *파일 시스템 동기화 그룹*을 사용하므로
`RetroPhone/` 아래에 `.swift` 파일을 추가하면 자동으로 빌드에 포함됩니다.

## 문서
- [기능별 구현·검증 상태, 테스트 결과, 제한 사항, 미해결 문제](docs/STATUS.md)
- [OldOS 분석 및 라이선스 판단](docs/OLDOS_ANALYSIS.md)
- [외부 앱 실행 지원 현황](docs/EXTERNAL_APPS.md)
- [아키텍처](docs/ARCHITECTURE.md)

## 도구
- `scripts/check_l10n.py` — 영어 번역이 빠진 문자열과 중복 키(런타임 크래시 원인) 검사
- `scripts/make_app_icon.swift` — 앱 아이콘(1024px) 생성

## 출처 및 라이선스
- The OldOS Project © Zane Kleinberg — CC BY 4.0. 구조와 동작을 참고했으며 코드는 새로 작성, Apple 원본 에셋은 미사용.
- 날씨 데이터: [Open-Meteo](https://open-meteo.com/) (CC BY 4.0, 비상업적 사용).
- iPhone, iOS는 Apple Inc.의 상표이며, 외부 앱 이름은 각 소유자의 상표입니다. 본 프로젝트는 이들과 무관합니다.
- 앱스토어 배포 가능성(심사 지침 2.5.8 — 데스크톱/홈 화면 대체 형태의 앱, 4.1 모방 등)은 별도 검토가 필요합니다.
