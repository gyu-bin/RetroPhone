import Foundation

// English for Browser, Notes, Weather, Calculator and Maps.
// Keys already present in `EnglishTable.core` / `.home` / `.widgets` (취소, 완료, 검색, 오늘, 최고,
// 현재 위치, 새로운 메모, 지우기, 오프라인 …) are intentionally not repeated here.
extension EnglishTable {
    static let appsUtility: [String: String] = [
        // Browser
        "주소 입력": "Address", "주소를 입력하거나 검색하세요": "Enter an address or search",
        "새로 고침": "Reload", "중단": "Stop", "앞으로": "Forward", "공유": "Share",
        "북마크": "Bookmarks", "북마크 없음": "No Bookmarks", "북마크됨": "Bookmarked",
        "현재 페이지 추가": "Add Current Page", "검색 엔진": "Search Engine", "네이버": "Naver",
        "검색 필드에서 사용할 검색 엔진을 선택하세요.": "Choose the search engine used by the search field.",
        "새로운 페이지": "New Page", "페이지 닫기": "Close Page", "페이지 %d개": "%d pages",
        "페이지를 열 수 없음": "Cannot Open Page", "제목 없음": "Untitled",

        // Notes
        "메모 (%d)": "Notes (%d)", "메모 내용": "Note text", "메모 삭제": "Delete Note",
        "이 메모를 삭제하시겠습니까?": "Delete this note?", "이전 메모": "Previous Note", "다음 메모": "Next Note",
        "결과 없음": "No Results",

        // Weather
        "날씨 설정": "Weather Settings", "단위": "Unit", "위치": "Location", "도시 검색": "Find a City",
        "도시 이름": "City name", "도시 선택": "Choose City", "검색 결과가 없습니다": "No results found",
        "위치 권한이 꺼져 있습니다": "Location access is off",
        "위치 권한이 꺼져 있어 저장된 정보를 표시합니다": "Location access is off — showing saved weather",
        "iOS 설정에서 위치 접근을 허용하거나, 뒷면에서 도시를 지정하세요.": "Allow location access in iOS Settings, or choose a city on the back.",
        "업데이트 중…": "Updating…", "업데이트: %@": "Updated %@", "오래된 정보입니다": "This information is out of date",
        "저장된 정보를 표시합니다": "showing saved weather", "지금": "Now", "일출": "Sunrise", "일몰": "Sunset",
        "데이터: Open-Meteo (CC BY 4.0)": "Data: Open-Meteo (CC BY 4.0)",

        // Calculator
        "메모리 지우기": "Memory clear", "메모리 더하기": "Memory add", "메모리 빼기": "Memory subtract",
        "메모리 불러오기": "Memory recall", "모두 지우기": "All clear", "부호 바꾸기": "Change sign",
        "나누기": "Divide", "곱하기": "Multiply", "빼기": "Subtract", "더하기": "Add", "소수점": "Decimal point",
        "계산": "Equals", "복사": "Copy",

        // Maps
        "검색 또는 주소": "Search or Address", "검색 결과 목록": "Search results", "경로": "Route",
        "경로 지우기": "Clear Route", "경로를 찾을 수 없습니다": "Directions Not Available",
        "지도 앱에서 열기": "Open in Maps", "옵션": "Options", "핀 꽂기": "Drop Pin", "놓은 핀": "Dropped Pin",
        "교통 정보": "Traffic", "표준": "Standard", "위성": "Satellite", "하이브리드": "Hybrid",
        "지도 데이터 © Apple 및 데이터 제공자": "Map data © Apple and data providers",
        "위치 서비스 꺼짐": "Location Services Off",
        "현재 위치를 보려면 iOS 설정에서 위치 접근을 허용하세요. 검색은 계속 사용할 수 있습니다.": "To see your current location, allow location access in iOS Settings. Search still works.",
    ]
}
