import Foundation

/// Apps implemented inside RetroPhone.
enum BuiltinApp: String, Codable, CaseIterable, Identifiable {
    case phone, messages, contacts, photos, camera, music, browser, notes
    case calendar, weather, calculator, clock, maps, voiceMemos, settings
    var id: String { rawValue }
    var appID: AppID { AppID("builtin.\(rawValue)") }

    var nameKo: String {
        switch self {
        case .phone: "전화"; case .messages: "메시지"; case .contacts: "연락처"
        case .photos: "사진"; case .camera: "카메라"; case .music: "음악"
        case .browser: "브라우저"; case .notes: "메모"; case .calendar: "캘린더"
        case .weather: "날씨"; case .calculator: "계산기"; case .clock: "시계"
        case .maps: "지도"; case .voiceMemos: "음성 메모"; case .settings: "설정"
        }
    }

    /// URL that opens the real Apple app (community-known schemes; nil where none exists).
    var systemURL: String? {
        switch self {
        case .messages: "sms:"
        case .maps: "maps://"
        case .calendar: "calshow://"
        case .notes: "mobilenotes://"
        case .weather: "weather://"
        case .music: "music://"
        case .photos: "photos-redirect://"
        case .browser: "x-web-search://"
        case .clock: "clock-worldclock://"
        case .voiceMemos: "voicememos://"
        default: nil
        }
    }

    var art: IconArt {
        switch self {
        case .phone: .phone; case .messages: .messages; case .contacts: .contacts
        case .photos: .photos; case .camera: .camera; case .music: .music
        case .browser: .browser; case .notes: .notes; case .calendar: .calendar
        case .weather: .weather; case .calculator: .calculator; case .clock: .clock
        case .maps: .maps; case .voiceMemos: .voiceMemos; case .settings: .settings
        }
    }
}

/// Stable identifier for anything that can sit on the home screen as an app icon.
/// Formats: `builtin.<name>`, `ext.<name>`, `custom.<uuid>`.
struct AppID: Codable, Hashable, Identifiable, ExpressibleByStringLiteral, CustomStringConvertible {
    let raw: String
    init(_ raw: String) { self.raw = raw }
    init(stringLiteral value: String) { raw = value }
    init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(raw) }
    var id: String { raw }
    var description: String { raw }

    var builtin: BuiltinApp? {
        guard raw.hasPrefix("builtin.") else { return nil }
        return BuiltinApp(rawValue: String(raw.dropFirst(8)))
    }
    var isExternal: Bool { raw.hasPrefix("ext.") || raw.hasPrefix("custom.") }
}

/// How confident we are that an app's URL scheme is officially supported.
enum SchemeVerification: String, Codable {
    /// Documented by the vendor (developer docs / SDK guide).
    case documented
    /// Widely used but not found in official vendor docs — may break at any time.
    case community
    /// No app scheme; we only open the web / universal link.
    case webOnly
}

/// An external (third-party) app that RetroPhone can launch via URL scheme / universal link.
struct ExternalApp: Codable, Hashable, Identifiable {
    var id: AppID
    var nameKo: String
    var nameEn: String
    var scheme: String?          // e.g. "kakaotalk://"
    var webURL: String?          // universal link or website fallback
    var appStoreID: String?
    var verification: SchemeVerification
    var art: IconArt
    /// Extra spellings recognized by the screenshot importer (OCR), e.g. "카톡".
    var aliases: [String]? = nil
    /// Apple system app (opened via its system URL scheme).
    var isSystem: Bool? = nil

    var displayName: String { Localizer.shared.language == .ko ? nameKo : nameEn }
}

enum AppCatalog {
    /// Priority external apps from the spec. Schemes were checked against public vendor
    /// documentation on 2026-11-24 (see docs/EXTERNAL_APPS.md): only NAVER Map and Spotify are
    /// documented by the vendor; `community` entries are best-effort and fall back to the web link.
    static let externalApps: [ExternalApp] = priorityApps + moreApps + systemApps

    /// The 12 apps named in the original spec.
    static let priorityApps: [ExternalApp] = [
        ExternalApp(id: "ext.kakaotalk", nameKo: "카카오톡", nameEn: "KakaoTalk", scheme: "kakaotalk://",
                    webURL: "https://www.kakaocorp.com/page/service/service/KakaoTalk", appStoreID: "362057947",
                    verification: .community, art: .chatBubbleYellow),
        ExternalApp(id: "ext.instagram", nameKo: "인스타그램", nameEn: "Instagram", scheme: "instagram://app",
                    webURL: "https://www.instagram.com/", appStoreID: "389801252",
                    verification: .community, art: .instantCamera),
        ExternalApp(id: "ext.youtube", nameKo: "유튜브", nameEn: "YouTube", scheme: "youtube://",
                    webURL: "https://www.youtube.com/", appStoreID: "544007664",
                    verification: .community, art: .crtTV),
        ExternalApp(id: "ext.naver", nameKo: "네이버", nameEn: "NAVER", scheme: "naversearchapp://",
                    webURL: "https://m.naver.com/", appStoreID: "393499958",
                    verification: .community, art: .searchGreen),
        ExternalApp(id: "ext.navermap", nameKo: "네이버 지도", nameEn: "NAVER Map", scheme: "nmap://",
                    webURL: "https://map.naver.com/", appStoreID: "311867728",
                    verification: .documented, art: .mapGreen),
        ExternalApp(id: "ext.kakaomap", nameKo: "카카오맵", nameEn: "KakaoMap", scheme: "kakaomap://",
                    webURL: "https://map.kakao.com/", appStoreID: "304608425",
                    verification: .community, art: .mapPinYellow),
        ExternalApp(id: "ext.toss", nameKo: "토스", nameEn: "Toss", scheme: "supertoss://",
                    webURL: "https://toss.im/", appStoreID: "839333328",
                    verification: .community, art: .wallet),
        ExternalApp(id: "ext.chatgpt", nameKo: "ChatGPT", nameEn: "ChatGPT", scheme: nil,
                    webURL: "https://chatgpt.com/", appStoreID: "6448311069",
                    verification: .webOnly, art: .robot),
        ExternalApp(id: "ext.gmail", nameKo: "Gmail", nameEn: "Gmail", scheme: "googlegmail://",
                    webURL: "https://mail.google.com/", appStoreID: "422689480",
                    verification: .community, art: .envelope),
        ExternalApp(id: "ext.netflix", nameKo: "넷플릭스", nameEn: "Netflix", scheme: "nflx://",
                    webURL: "https://www.netflix.com/", appStoreID: "363590051",
                    verification: .community, art: .filmReel),
        ExternalApp(id: "ext.coupang", nameKo: "쿠팡", nameEn: "Coupang", scheme: "coupang://",
                    webURL: "https://www.coupang.com/", appStoreID: "454434967",
                    verification: .community, art: .shoppingBag),
        ExternalApp(id: "ext.spotify", nameKo: "Spotify", nameEn: "Spotify", scheme: "spotify://",
                    webURL: "https://open.spotify.com/", appStoreID: "324684580",
                    verification: .documented, art: .vinyl),
    ]

    static func external(_ id: AppID, custom: [ExternalApp] = []) -> ExternalApp? {
        externalApps.first { $0.id == id } ?? custom.first { $0.id == id }
    }

    /// Default display name (before user renames).
    static func defaultName(_ id: AppID, custom: [ExternalApp] = []) -> String {
        if let b = id.builtin { return L(b.nameKo) }
        return external(id, custom: custom)?.displayName ?? "?"
    }

    static func defaultArt(_ id: AppID, custom: [ExternalApp] = []) -> IconArt {
        if let b = id.builtin { return b.art }
        return external(id, custom: custom)?.art ?? .generic
    }
}
