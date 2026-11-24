import Foundation

/// Additional third-party apps and Apple system apps. Schemes marked `.community` are widely used but
/// not documented by the vendor; `.webOnly` apps open their universal link (which launches the app
/// when installed). Every entry falls back to its web link if the scheme fails.
extension AppCatalog {
    private static func app(_ key: String, _ ko: String, _ en: String, scheme: String? = nil, web: String? = nil,
                            _ v: SchemeVerification = .community, art: IconArt, aliases: [String] = []) -> ExternalApp {
        ExternalApp(id: AppID("ext.\(key)"), nameKo: ko, nameEn: en, scheme: scheme, webURL: web, appStoreID: nil,
                    verification: scheme == nil ? .webOnly : v, art: art, aliases: aliases)
    }

    static let moreApps: [ExternalApp] = [
        // Messaging & social
        app("line", "라인", "LINE", scheme: "line://", web: "https://line.me/", art: .chatGreen),
        app("whatsapp", "왓츠앱", "WhatsApp", scheme: "whatsapp://", web: "https://www.whatsapp.com/", .documented, art: .chatGreen),
        app("telegram", "텔레그램", "Telegram", scheme: "tg://", web: "https://telegram.org/", art: .chatBlue),
        app("discord", "디스코드", "Discord", scheme: "discord://", web: "https://discord.com/app", art: .chatPurple),
        app("facebook", "페이스북", "Facebook", scheme: "fb://", web: "https://www.facebook.com/", art: .people),
        app("x", "X", "X", scheme: "twitter://", web: "https://x.com/", art: .atSign, aliases: ["트위터", "Twitter"]),
        app("threads", "스레드", "Threads", web: "https://www.threads.net/", art: .chatDark, aliases: ["Threads"]),
        app("tiktok", "틱톡", "TikTok", web: "https://www.tiktok.com/", art: .musicPurple),
        app("pinterest", "핀터레스트", "Pinterest", scheme: "pinterest://", web: "https://www.pinterest.com/", art: .pin),
        app("reddit", "레딧", "Reddit", scheme: "reddit://", web: "https://www.reddit.com/", art: .chatDark),
        app("linkedin", "링크드인", "LinkedIn", scheme: "linkedin://", web: "https://www.linkedin.com/", art: .briefcase),
        app("band", "밴드", "BAND", scheme: "bandapp://", web: "https://band.us/", art: .people, aliases: ["네이버 밴드"]),
        // Work & productivity
        app("slack", "슬랙", "Slack", scheme: "slack://", web: "https://app.slack.com/", art: .briefcase),
        app("notion", "노션", "Notion", scheme: "notion://", web: "https://www.notion.so/", art: .docs),
        app("zoom", "줌", "Zoom", scheme: "zoomus://", web: "https://zoom.us/", art: .videoCall, aliases: ["Zoom Workplace"]),
        app("teams", "팀즈", "Teams", scheme: "msteams://", web: "https://teams.microsoft.com/", art: .briefcase, aliases: ["Microsoft Teams"]),
        app("outlook", "아웃룩", "Outlook", scheme: "ms-outlook://", web: "https://outlook.live.com/", art: .mailBlue),
        app("google", "구글", "Google", scheme: "google://", web: "https://www.google.com/", art: .searchBlue),
        app("chrome", "크롬", "Chrome", scheme: "googlechrome://", web: "https://www.google.com/chrome/", art: .globe),
        app("googlemaps", "구글 지도", "Google Maps", scheme: "comgooglemaps://", web: "https://maps.google.com/", .documented, art: .mapGreen),
        app("gdrive", "구글 드라이브", "Google Drive", scheme: "googledrive://", web: "https://drive.google.com/", art: .cloudDrive, aliases: ["Drive"]),
        app("papago", "파파고", "Papago", scheme: "papago://", web: "https://papago.naver.com/", art: .translate),
        app("navermail", "네이버 메일", "NAVER Mail", web: "https://mail.naver.com/", art: .mailBlue),
        app("gemini", "Gemini", "Gemini", web: "https://gemini.google.com/", art: .sparkle),
        app("claude", "Claude", "Claude", web: "https://claude.ai/", art: .sparkle),
        // Media & entertainment
        app("youtubemusic", "유튜브 뮤직", "YouTube Music", scheme: "youtubemusic://", web: "https://music.youtube.com/", art: .playRed, aliases: ["YT Music"]),
        app("melon", "멜론", "Melon", scheme: "melonapp://", web: "https://www.melon.com/", art: .musicGreen),
        app("genie", "지니", "genie", scheme: "genie://", web: "https://www.genie.co.kr/", art: .musicPurple, aliases: ["지니뮤직"]),
        app("tving", "티빙", "TVING", scheme: "tving://", web: "https://www.tving.com/", art: .tvDark),
        app("wavve", "웨이브", "wavve", web: "https://www.wavve.com/", art: .tvDark),
        app("coupangplay", "쿠팡플레이", "Coupang Play", scheme: "coupangplay://", web: "https://www.coupangplay.com/", art: .tvDark),
        app("disneyplus", "디즈니+", "Disney+", scheme: "disneyplus://", web: "https://www.disneyplus.com/", art: .tvDark, aliases: ["디즈니플러스"]),
        app("watcha", "왓챠", "WATCHA", web: "https://watcha.com/", art: .tvDark),
        app("webtoon", "네이버 웹툰", "WEBTOON", scheme: "naverwebtoon://", web: "https://comic.naver.com/", art: .webtoon, aliases: ["웹툰"]),
        app("kakaopage", "카카오페이지", "KakaoPage", web: "https://page.kakao.com/", art: .books),
        app("twitch", "치지직", "CHZZK", web: "https://chzzk.naver.com/", art: .playRed),
        // Finance
        app("kakaobank", "카카오뱅크", "KakaoBank", scheme: "kakaobank://", web: "https://www.kakaobank.com/", art: .bankYellow),
        app("kakaopay", "카카오페이", "KakaoPay", scheme: "kakaopay://", web: "https://www.kakaopay.com/", art: .payYellow),
        app("kbbank", "KB스타뱅킹", "KB Star Banking", web: "https://obank.kbstar.com/", art: .bankNavy, aliases: ["KB 스타뱅킹", "스타뱅킹"]),
        app("shinhan", "신한 SOL뱅크", "Shinhan SOL", web: "https://www.shinhan.com/", art: .bankBlue, aliases: ["SOL", "신한SOL뱅크", "신한 SOL"]),
        app("woori", "우리WON뱅킹", "Woori WON", web: "https://www.wooribank.com/", art: .bankBlue, aliases: ["우리은행"]),
        app("hana", "하나원큐", "Hana 1Q", web: "https://www.kebhana.com/", art: .bankBlue),
        app("upbit", "업비트", "Upbit", web: "https://upbit.com/", art: .chart),
        // Shopping & food
        app("baemin", "배달의민족", "Baemin", scheme: "baemin://", web: "https://www.baemin.com/", art: .delivery, aliases: ["배민"]),
        app("coupangeats", "쿠팡이츠", "Coupang Eats", scheme: "coupangeats://", web: "https://www.coupangeats.com/", art: .delivery),
        app("yogiyo", "요기요", "Yogiyo", scheme: "yogiyo://", web: "https://www.yogiyo.co.kr/", art: .delivery),
        app("daangn", "당근", "Karrot", scheme: "towneers://", web: "https://www.daangn.com/", art: .carrot, aliases: ["당근마켓"]),
        app("bunjang", "번개장터", "Bunjang", scheme: "bunjang://", web: "https://m.bunjang.co.kr/", art: .bolt),
        app("musinsa", "무신사", "MUSINSA", web: "https://www.musinsa.com/", art: .tshirt),
        app("elevenst", "11번가", "11st", web: "https://www.11st.co.kr/", art: .cart),
        app("gmarket", "G마켓", "Gmarket", web: "https://www.gmarket.co.kr/", art: .cart),
        app("oliveyoung", "올리브영", "OLIVE YOUNG", web: "https://www.oliveyoung.co.kr/", art: .shoppingBag),
        app("starbucks", "스타벅스", "Starbucks", web: "https://www.starbucks.co.kr/", art: .coffee),
        // Travel & mobility
        app("kakaot", "카카오 T", "Kakao T", scheme: "kakaot://", web: "https://www.kakaomobility.com/", art: .taxi, aliases: ["카카오T"]),
        app("tmap", "티맵", "TMAP", scheme: "tmap://", web: "https://www.tmap.co.kr/", art: .navigation),
        app("uber", "우버", "Uber", scheme: "uber://", web: "https://m.uber.com/", art: .taxi),
        app("airbnb", "에어비앤비", "Airbnb", scheme: "airbnb://", web: "https://www.airbnb.com/", art: .plane),
        app("yanolja", "야놀자", "Yanolja", web: "https://www.yanolja.com/", art: .bed),
        app("goodchoice", "여기어때", "Yeogi", web: "https://www.goodchoice.kr/", art: .bed),
        app("korail", "코레일톡", "Korail Talk", web: "https://www.letskorail.com/", art: .ticket),
        app("zigbang", "직방", "Zigbang", web: "https://www.zigbang.com/", art: .house),
    ]

    /// Apple apps that RetroPhone doesn't re-implement; tapping opens the real app.
    static let systemApps: [ExternalApp] = [
        sys("appstore", "App Store", "App Store", "itms-apps://", art: .appStore, aliases: ["앱스토어"]),
        sys("mail", "메일", "Mail", "message://", art: .mailBlue),
        sys("facetime", "FaceTime", "FaceTime", "facetime://", art: .videoCall, .documented),
        sys("wallet", "지갑", "Wallet", "shoebox://", art: .walletDark, aliases: ["Wallet"]),
        sys("health", "건강", "Health", "x-apple-health://", art: .heart),
        sys("shortcuts", "단축어", "Shortcuts", "shortcuts://", art: .layers, .documented),
        sys("files", "파일", "Files", "shareddocuments://", art: .folderBlue),
        sys("reminders", "미리 알림", "Reminders", "x-apple-reminderkit://", art: .checklist),
        sys("podcasts", "팟캐스트", "Podcasts", "podcasts://", art: .podcast),
        sys("tv", "TV", "TV", "videos://", art: .tvDark),
        sys("home", "홈", "Home", "com.apple.home://", art: .house),
        sys("findmy", "나의 찾기", "Find My", "findmy://", art: .radar, aliases: ["찾기"]),
        sys("books", "도서", "Books", "ibooks://", art: .books),
        sys("iosmessages", "iOS 메시지", "iOS Messages", "sms:", art: .messages),
        sys("iossafari", "Safari", "Safari", "x-web-search://", art: .browser, aliases: ["사파리"]),
    ]

    private static func sys(_ key: String, _ ko: String, _ en: String, _ scheme: String, art: IconArt,
                            _ v: SchemeVerification = .community, aliases: [String] = []) -> ExternalApp {
        ExternalApp(id: AppID("sys.\(key)"), nameKo: ko, nameEn: en, scheme: scheme, webURL: nil, appStoreID: nil,
                    verification: v, art: art, aliases: aliases, isSystem: true)
    }

    /// Up to 50 schemes probed with canOpenURL to find installed apps (iOS limit). Must match Info.plist.
    static let probedSchemes: [String] = [
        "kakaotalk", "instagram", "youtube", "naversearchapp", "nmap", "kakaomap", "supertoss", "googlegmail",
        "nflx", "coupang", "spotify", "line", "whatsapp", "tg", "discord", "fb", "twitter", "pinterest", "reddit",
        "linkedin", "bandapp", "slack", "notion", "zoomus", "msteams", "ms-outlook", "google", "googlechrome",
        "comgooglemaps", "googledrive", "papago", "youtubemusic", "melonapp", "genie", "tving", "coupangplay",
        "disneyplus", "naverwebtoon", "kakaobank", "kakaopay", "baemin", "coupangeats", "yogiyo", "towneers",
        "bunjang", "kakaot", "tmap", "uber", "airbnb",
    ]
}
