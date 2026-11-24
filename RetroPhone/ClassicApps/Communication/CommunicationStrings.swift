import Foundation

extension EnglishTable {
    static let appsCommunication: [String: String] = [
        // Shared
        "정보": "Info", "열 수 없음": "Can't Open", "이 기기에서는 이 작업을 할 수 없습니다.": "This device can't do that.",
        "접근 허용": "Allow Access", "검색 결과 없음": "No Results", "이름 없음": "No Name",
        "통화": "Call", "통화할 수 없음": "Cannot Make Call", "이 기기에서는 전화를 걸 수 없습니다.": "This device can't make phone calls.",

        // Contacts
        "모든 연락처": "All Contacts", "연락처 없음": "No Contacts", "%d개의 연락처": "%d Contacts",
        "연락처 접근": "Contacts Access",
        "기기의 연락처를 보려면 접근을 허용하세요. 연락처는 기기 밖으로 전송되지 않습니다.": "Allow access to see the contacts on this device. Contacts never leave the device.",
        "연락처 접근이 거부됨": "Contacts Access Denied",
        "iOS 설정 > RetroPhone에서 연락처 접근을 허용하세요.": "Allow Contacts access in iOS Settings > RetroPhone.",
        "연락처 접근이 제한됨": "Contacts Access Restricted",
        "이 기기에서는 연락처 접근이 제한되어 있습니다(스크린 타임 또는 기기 관리).": "Contacts access is restricted on this device (Screen Time or device management).",
        "선택한 연락처만 RetroPhone에서 볼 수 있습니다.": "RetroPhone can only see the contacts you selected.",
        "연락처 더 선택…": "Select More Contacts…",
        "휴대전화": "mobile", "기본": "main", "집": "home", "직장": "work", "기타": "other",
        "집 팩스": "home fax", "직장 팩스": "work fax", "호출기": "pager", "홈페이지": "home page", "학교": "school",
        "생일": "birthday", "문자 보내기": "Text Message", "즐겨찾기에 추가": "Add to Favorites",
        "즐겨찾기에 추가됨": "Added to Favorites", "전화번호 없음": "No Phone Number",
        "이 연락처에는 전화번호가 없습니다.": "This contact has no phone number.",

        // Phone
        "즐겨찾기": "Favorites", "최근 통화": "Recents", "키패드": "Keypad", "음성 사서함": "Voicemail",
        "번호 없음": "No number", "즐겨찾기 없음": "No Favorites", "즐겨찾기 추가": "Add Favorite",
        "+ 버튼으로 연락처의 전화번호를 추가하세요. 즐겨찾기는 이 기기의 RetroPhone에만 저장됩니다.": "Tap + to add a contact's number. Favorites are stored only in RetroPhone on this device.",
        "iOS는 다른 앱에 기기의 통화 기록을 제공하지 않습니다. 이곳에는 RetroPhone에서 건 전화만 표시됩니다.": "iOS doesn't share the device's call history with other apps. Only calls placed from RetroPhone are shown here.",
        "RetroPhone에서 건 전화가 없습니다.": "No calls placed from RetroPhone.",
        "RetroPhone에서 건 전화": "Calls from RetroPhone", "최근 기록 지우기": "Clear All Recents",
        "음성 사서함을 표시할 수 없음": "Voicemail Unavailable",
        "iOS는 다른 앱이 음성 사서함에 접근하도록 허용하지 않습니다. 음성 사서함은 기본 전화 앱에서 확인하세요.": "iOS doesn't allow other apps to access voicemail. Check voicemail in the built-in Phone app.",

        // Messages
        "새로운 메시지": "New Message", "기존 대화는 표시할 수 없음": "Existing Conversations Unavailable",
        "iOS는 다른 앱이 문자·iMessage 기록을 읽도록 허용하지 않습니다. 오른쪽 위 버튼으로 새 메시지를 작성하면 iOS 메시지 작성 화면을 통해 전송되고, 보낸 내용만 이 기기의 RetroPhone에 기록됩니다.": "iOS doesn't let other apps read SMS or iMessage history. Compose a new message with the top-right button: it's sent through the iOS message composer, and only what you send is recorded in RetroPhone on this device.",
        "RetroPhone에서 보낸 메시지만 표시됩니다": "Only messages sent from RetroPhone are shown",
        "RetroPhone에서 iOS 메시지 작성 화면으로 전송한 내용입니다. 작성 화면에서 수정한 내용과 상대방의 답장은 표시되지 않습니다.": "Messages sent from RetroPhone through the iOS composer. Edits made in the composer and replies are not shown.",
        "메시지를 보낼 수 없음": "Cannot Send Message", "이 기기에서는 문자 메시지를 보낼 수 없습니다.": "This device can't send text messages.",
        "문자 메시지": "Text Message", "보내기": "Send", "받는 사람:": "To:", "받는 사람 선택": "Choose Recipient",
        "받는 사람 없음": "No Recipient", "받는 사람의 전화번호나 이메일을 입력하세요.": "Enter the recipient's phone number or email.",
        "연락처에서 선택": "Choose from Contacts", "%@ 삭제": "Remove %@",
        "메시지는 iOS 메시지 작성 화면을 통해 전송됩니다.": "Messages are sent through the iOS message composer.",

        // Calendar
        "목록": "List", "일": "Day", "월": "Month", "일정 없음": "No Events", "계속": "cont.",
        "앞으로 90일 동안 일정 없음": "No events in the next 90 days", "정오": "Noon",
        "캘린더 접근": "Calendar Access", "기기의 캘린더 일정을 표시하고 편집하려면 접근을 허용하세요.": "Allow access to show and edit the events on this device.",
        "캘린더 접근이 거부됨": "Calendar Access Denied",
        "일정을 보고 편집하려면 iOS 설정 > RetroPhone에서 캘린더 전체 접근을 허용하세요.": "To see and edit events, allow Full Calendar Access in iOS Settings > RetroPhone.",
        "일정 정보": "Event", "새로운 일정": "New Event", "반복": "Repeat", "알림": "Alert", "두 번째 알림": "Second Alert",
        "일정 삭제": "Delete Event", "이 일정만 삭제": "Delete This Event Only", "이후 모든 일정 삭제": "Delete All Future Events",
        "삭제할 수 없음": "Can't Delete", "이 일정을 삭제하지 못했습니다.": "This event couldn't be deleted.",
        "시작": "Start", "종료": "End", "일정 시간": "At time of event",
        "%d분 전": "%d minutes before", "%d분 후": "%d minutes after", "%d시간 전": "%d hours before", "%d일 전": "%d days before",
        "매일": "Every Day", "매주": "Every Week", "매월": "Every Month", "매년": "Every Year",
        "%d일마다": "Every %d days", "%d주마다": "Every %d weeks", "%d개월마다": "Every %d months", "%d년마다": "Every %d years",
        "사용자 설정": "Custom", "모두 보기": "Show All", "모두 숨기기": "Hide All",
        "숨긴 캘린더의 일정은 RetroPhone 캘린더에만 표시되지 않으며, 실제 캘린더는 변경되지 않습니다.": "Events from hidden calendars are only hidden in RetroPhone's Calendar; your actual calendars are unchanged.",

        // Clock
        "세계 시계": "World Clock", "알람": "Alarm", "스톱워치": "Stopwatch", "타이머": "Timer",
        "세계 시계 없음": "No World Clocks", "현지 시간": "Local time", "%+d시간": "%+d hrs", "%+.1f시간": "%+.1f hrs",
        "도시 선택": "Choose a City", "도시 또는 지역 검색": "Search city or region",
        "아시아": "Asia", "유럽": "Europe", "아메리카": "America", "아프리카": "Africa", "오스트레일리아": "Australia",
        "태평양": "Pacific", "대서양": "Atlantic", "인도양": "Indian Ocean", "남극": "Antarctica", "북극": "Arctic",
        "알람 없음": "No Alarms", "알람 추가": "Add Alarm", "알람 편집": "Edit Alarm", "알람 삭제": "Delete Alarm",
        "레이블": "Label", "사운드": "Sound", "iOS 기본 알림음": "iOS default sound", "안 함": "Never",
        "주중": "Weekdays", "주말": "Weekends", "%@마다": "Every %@",
        "알람은 iOS 알림으로 울립니다. 무음 모드나 집중 모드에서는 소리가 나지 않을 수 있으며, RetroPhone은 기본 시계 앱의 알람을 제어하지 않습니다.": "Alarms ring as iOS notifications. They may be silent in Silent mode or a Focus, and RetroPhone doesn't control the built-in Clock app's alarms.",
        "알람은 iOS 알림으로 전달됩니다. 다시 알림(스누즈)은 지원하지 않습니다.": "Alarms are delivered as iOS notifications. Snooze isn't supported.",
        "알림이 꺼져 있음": "Notifications Are Off",
        "알람을 울리려면 iOS 설정 > RetroPhone에서 알림을 허용하세요.": "To ring alarms, allow notifications in iOS Settings > RetroPhone.",
        "랩": "Lap", "랩 %d": "Lap %d", "재설정": "Reset", "정지": "Stop",
        "시간": "hours", "분": "min", "초": "sec", "재개": "Resume", "일시 정지됨": "Paused",
        "타이머 종료 시": "When Timer Ends", "알림음": "Alert Sound", "타이머 완료": "Timer Done",
        "타이머가 종료되었습니다.": "Your timer has ended.",
        "RetroPhone이 백그라운드에 있거나 화면이 꺼져 있으면 iOS 알림으로 종료를 알려줍니다.": "If RetroPhone is in the background or the screen is off, an iOS notification tells you when the timer ends.",
    ]
}
