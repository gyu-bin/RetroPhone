import Foundation
import Observation

/// App-internal language. Korean is the default; English is the alternative.
/// The language can be switched at runtime from Settings without relaunching,
/// which is why we don't rely on the system bundle localization for UI strings.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case ko, en
    var id: String { rawValue }
    var displayName: String { self == .ko ? "한국어" : "English" }
    var locale: Locale { Locale(identifier: self == .ko ? "ko_KR" : "en_US") }
}

@Observable
final class Localizer {
    static let shared = Localizer()
    var language: AppLanguage = .ko
}

/// Localize a Korean source string. Korean text is the key; English comes from `EnglishTable`.
/// Reading `Localizer.shared.language` inside a SwiftUI body registers an Observation
/// dependency, so views re-render automatically when the language changes.
func L(_ ko: String) -> String {
    guard Localizer.shared.language == .en else { return ko }
    return EnglishTable.map[ko] ?? ko
}

/// Localize a format string, e.g. `LF("%d개의 항목", count)`.
func LF(_ ko: String, _ args: CVarArg...) -> String {
    String(format: L(ko), locale: Localizer.shared.language.locale, arguments: args)
}

/// Korean → English table. Each module contributes its own dictionary in its own file
/// (`extension EnglishTable { static let xyz: [String: String] = [...] }`) so modules can be
/// edited independently; they are merged here.
enum EnglishTable {
    static let map: [String: String] = {
        var all: [String: String] = [:]
        for table in [core, lock, home, widgets, settings, setup, launcher,
                      appsCommunication, appsMedia, appsUtility] {
            all.merge(table) { current, _ in current }
        }
        return all
    }()

    static let core: [String: String] = [
        "확인": "OK", "취소": "Cancel", "완료": "Done", "편집": "Edit", "삭제": "Delete",
        "저장": "Save", "닫기": "Close", "추가": "Add", "뒤로": "Back", "검색": "Search",
        "설정": "Settings", "설정 열기": "Open Settings", "다시 시도": "Try Again",
        "권한이 필요합니다": "Permission Required",
        "이 기능을 사용하려면 iOS 설정에서 접근을 허용하세요.": "Allow access in iOS Settings to use this feature.",
        "네트워크에 연결되어 있지 않습니다": "Not connected to the network",
        "불러오는 중…": "Loading…", "항목 없음": "No Items", "오류": "Error",
        "오늘": "Today", "어제": "Yesterday", "내일": "Tomorrow",
        "전화": "Phone", "메시지": "Messages", "연락처": "Contacts", "사진": "Photos",
        "카메라": "Camera", "음악": "Music", "브라우저": "Browser", "메모": "Notes",
        "캘린더": "Calendar", "날씨": "Weather", "계산기": "Calculator", "시계": "Clock",
        "지도": "Maps", "음성 메모": "Voice Memos",
    ]
}
