# 외부 앱 실행 지원 현황

실행 순서: **① 앱 URL 스킴 → ② 웹/유니버설 링크 → ③ 실패 시 App Store 안내**.
`canOpenURL` 확인을 위해 스킴은 `Config/Info.plist`의 `LSApplicationQueriesSchemes`에 선언했습니다(최대 50개).

> 검증 수준: 아래 "근거"는 2026-11-24 웹 검색으로 확인한 공개 문서 기준이며, **실기기에서 각 앱을 설치해 실행해 본 검증은
> 아직 하지 않았습니다**(시뮬레이터에는 해당 앱들이 없음). 스킴은 앱 업데이트로 바뀔 수 있습니다.

| 앱 | 스킴 | 대체 링크 | 분류 | 근거 / 비고 |
|---|---|---|---|---|
| 카카오톡 | `kakaotalk://` | kakaocorp.com 서비스 페이지 | community | Kakao 공식 iOS 시작 가이드의 쿼리 스킴 목록에는 `kakaokompassauth`·`kakaolink`·`kakaoplus`만 있고 `kakaotalk`은 없음 (developers.kakao.com/docs/latest/ko/ios/getting-started) |
| 인스타그램 | `instagram://app` | instagram.com | community | Meta 공식 문서는 공유용 `instagram-stories`·`instagram-reels` 스킴만 안내. `instagram://app`은 커뮤니티 자료 기준 |
| 유튜브 | `youtube://` | youtube.com (유니버설 링크) | community | 공식 문서 없음. 유니버설 링크가 더 안정적 |
| 네이버 | `naversearchapp://` | m.naver.com | community | 공식 공개 문서 확인 못함 |
| 네이버 지도 | `nmap://` | map.naver.com | documented | NAVER Cloud 공식 Maps URL Scheme 가이드 (guide.ncloud-docs.com/docs/maps-url-scheme) — `appname` 파라미터 권장, 앱 v5+ |
| 카카오맵 | `kakaomap://` | map.kakao.com | community | 공식 문서 페이지는 찾지 못함. Kakao DevTalk 포럼에서 `kakaomap://route` 사용 사례 확인 |
| 토스 | `supertoss://` | toss.im | community | 공식 문서 없음 |
| ChatGPT | (없음) | chatgpt.com (유니버설 링크) | webOnly | 공개된 앱 스킴 문서 없음 — 앱 설치 시 유니버설 링크로 앱이 열림 |
| Gmail | `googlegmail://` | mail.google.com | community | Google 공식 문서 없음. 커뮤니티 자료 기준(작성 화면 외 경로는 동작 안 할 수 있음) |
| 넷플릭스 | `nflx://` | netflix.com | community | 공식 문서 없음 |
| 쿠팡 | `coupang://` | coupang.com | community | 공식 문서 없음 |
| Spotify | `spotify://` | open.spotify.com | documented | Spotify iOS SDK Quick Start / Content Linking 문서가 `spotify` 스킴과 LSApplicationQueriesSchemes 등록 안내 |

## 구현하지 않는 것 (iOS 정책상 불가)
- 설치된 전체 앱 목록 조회, 다른 앱의 알림 배지 조회, 다른 앱 UI 변경, 다른 앱 실행 상태 제어.

## 사용자 정의 바로가기
홈 화면 편집 › `+` › 직접 추가에서 임의 스킴(`myapp://`) 또는 웹 주소로 아이콘을 만들 수 있습니다.
`javascript:`, `data:`, `file:` 스킴은 차단합니다.
