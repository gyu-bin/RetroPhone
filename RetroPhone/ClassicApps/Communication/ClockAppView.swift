import SwiftUI
import Observation

/// iOS 4 Clock: black tab bar with World Clock / Alarm / Stopwatch / Timer.
struct ClockAppView: View {
    enum Tab: Hashable { case world, alarm, stopwatch, timer }

    @State private var tab: Tab = .world

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .world: ClockWorldView()
                case .alarm: ClockAlarmListView()
                case .stopwatch: ClockStopwatchView()
                case .timer: ClockTimerView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            CommTabBar(items: [
                CommTabItem(tag: Tab.world, title: L("세계 시계"), systemImage: "globe"),
                CommTabItem(tag: Tab.alarm, title: L("알람"), systemImage: "alarm.fill"),
                CommTabItem(tag: Tab.stopwatch, title: L("스톱워치"), systemImage: "stopwatch.fill"),
                CommTabItem(tag: Tab.timer, title: L("타이머"), systemImage: "timer"),
            ], selection: $tab)
        }
        .background(Color.black)
        .onAppear {
            ClockNotificationDelegate.shared.install()
            ClockAlarmStore.shared.refreshExpired()
            if ClockCountdown.shared.phase != .idle { tab = .timer }
        }
    }
}

// MARK: - World clock store

@Observable
final class ClockWorldStore {
    static let shared = ClockWorldStore()
    private static let file = "clock_world.json"

    private(set) var zones: [String]

    private init() {
        zones = FileStore.load([String].self, from: Self.file) ?? [TimeZone.current.identifier]
    }

    func add(_ identifier: String) {
        guard !zones.contains(identifier) else { return }
        zones.append(identifier)
        save()
    }

    func remove(at offsets: IndexSet) {
        zones.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        zones.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func save() { FileStore.save(zones, to: Self.file) }
}

// MARK: - City names (from the system time-zone database)

enum WorldCityNames {
    /// Korean names for common time-zone cities; everything else uses the identifier's city part.
    static let korean: [String: String] = [
        "Asia/Seoul": "서울", "Asia/Tokyo": "도쿄", "Asia/Shanghai": "상하이", "Asia/Hong_Kong": "홍콩",
        "Asia/Taipei": "타이베이", "Asia/Singapore": "싱가포르", "Asia/Bangkok": "방콕", "Asia/Ho_Chi_Minh": "호찌민",
        "Asia/Jakarta": "자카르타", "Asia/Manila": "마닐라", "Asia/Kolkata": "콜카타", "Asia/Dubai": "두바이",
        "Asia/Kuala_Lumpur": "쿠알라룸푸르", "Asia/Pyongyang": "평양", "Asia/Vladivostok": "블라디보스토크",
        "Asia/Kathmandu": "카트만두", "Asia/Karachi": "카라치", "Asia/Tehran": "테헤란", "Asia/Jerusalem": "예루살렘",
        "Asia/Riyadh": "리야드", "Asia/Ulaanbaatar": "울란바토르", "Asia/Almaty": "알마티", "Asia/Tashkent": "타슈켄트",
        "Europe/London": "런던", "Europe/Paris": "파리", "Europe/Berlin": "베를린", "Europe/Rome": "로마",
        "Europe/Madrid": "마드리드", "Europe/Amsterdam": "암스테르담", "Europe/Moscow": "모스크바",
        "Europe/Istanbul": "이스탄불", "Europe/Vienna": "빈", "Europe/Zurich": "취리히", "Europe/Prague": "프라하",
        "Europe/Athens": "아테네", "Europe/Stockholm": "스톡홀름", "Europe/Helsinki": "헬싱키", "Europe/Lisbon": "리스본",
        "Europe/Dublin": "더블린", "Europe/Brussels": "브뤼셀", "Europe/Warsaw": "바르샤바",
        "America/New_York": "뉴욕", "America/Chicago": "시카고", "America/Denver": "덴버",
        "America/Los_Angeles": "로스앤젤레스", "America/Toronto": "토론토", "America/Vancouver": "밴쿠버",
        "America/Mexico_City": "멕시코시티", "America/Sao_Paulo": "상파울루", "America/Argentina/Buenos_Aires": "부에노스아이레스",
        "America/Anchorage": "앵커리지", "America/Phoenix": "피닉스", "America/Bogota": "보고타", "America/Lima": "리마",
        "America/Santiago": "산티아고", "Pacific/Honolulu": "호놀룰루", "Pacific/Guam": "괌", "Pacific/Auckland": "오클랜드",
        "Australia/Sydney": "시드니", "Australia/Melbourne": "멜버른", "Australia/Brisbane": "브리즈번",
        "Australia/Perth": "퍼스", "Africa/Cairo": "카이로", "Africa/Johannesburg": "요하네스버그",
        "Africa/Nairobi": "나이로비", "Africa/Lagos": "라고스",
    ]

    static func englishName(_ id: String) -> String {
        let last = id.split(separator: "/").last.map(String.init) ?? id
        return last.replacingOccurrences(of: "_", with: " ")
    }

    static func name(_ id: String) -> String {
        if Localizer.shared.language == .ko, let ko = korean[id] { return ko }
        return englishName(id)
    }

    static func region(_ id: String) -> String {
        let first = id.split(separator: "/").first.map(String.init) ?? ""
        switch first {
        case "Asia": return L("아시아")
        case "Europe": return L("유럽")
        case "America": return L("아메리카")
        case "Africa": return L("아프리카")
        case "Australia": return L("오스트레일리아")
        case "Pacific": return L("태평양")
        case "Atlantic": return L("대서양")
        case "Indian": return L("인도양")
        case "Antarctica": return L("남극")
        case "Arctic": return L("북극")
        default: return first
        }
    }

    static func time(_ date: Date, in tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Localizer.shared.language.locale
        f.timeZone = tz
        let h24 = SettingsStore.shared.value.use24HourClock
        if h24 {
            f.dateFormat = "H:mm"
        } else {
            f.dateFormat = Localizer.shared.language == .ko ? "a h:mm" : "h:mm a"
        }
        return f.string(from: date)
    }

    /// "Today, +9 hrs" style subtitle relative to the device time zone.
    static func dayAndOffset(_ date: Date, _ tz: TimeZone) -> String {
        var remote = Calendar(identifier: .gregorian)
        remote.timeZone = tz
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone.current
        let r = remote.dateComponents([.year, .month, .day], from: date)
        let l = local.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        var dayDiff = 0
        if let rd = utc.date(from: r), let ld = utc.date(from: l) {
            dayDiff = utc.dateComponents([.day], from: ld, to: rd).day ?? 0
        }
        let day: String
        switch dayDiff {
        case 0: day = L("오늘")
        case 1: day = L("내일")
        case -1: day = L("어제")
        default: day = RetroFormat.date(date, template: "MMMd")
        }
        let diff = tz.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        if diff == 0 { return day + ", " + L("현지 시간") }
        if diff % 3600 == 0 { return day + ", " + LF("%+d시간", diff / 3600) }
        return day + ", " + LF("%+.1f시간", Double(diff) / 3600)
    }
}

// MARK: - World clock view

struct ClockWorldView: View {
    @State private var editMode: EditMode = .inactive
    @State private var showAdd = false

    private var store: ClockWorldStore { ClockWorldStore.shared }

    var body: some View {
        NavigationStack {
            ClassicPage(title: L("세계 시계"), background: AnyView(Color.black), leading: {
                if !store.zones.isEmpty {
                    ClassicBarButton(title: editMode.isEditing ? L("완료") : L("편집"),
                                     kind: editMode.isEditing ? .done : .plain) {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
            }, trailing: {
                ClassicBarButton(title: L("추가"), systemImage: "plus") { showAdd = true }
            }) {
                if store.zones.isEmpty {
                    Text(L("세계 시계 없음"))
                        .font(.retro(20, .bold))
                        .foregroundStyle(Color(hex: 0x8A8A8A))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.zones, id: \.self) { id in
                            ClockWorldRow(identifier: id)
                                .listRowBackground(
                                    LinearGradient(colors: [Color(hex: 0x2A2A2A), Color(hex: 0x111111)], startPoint: .top, endPoint: .bottom)
                                )
                                .listRowSeparatorTint(Color(hex: 0x444444))
                                .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 12))
                        }
                        .onDelete { store.remove(at: $0) }
                        .onMove { store.move(from: $0, to: $1) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.black)
                    .environment(\.editMode, $editMode)
                    .environment(\.colorScheme, .dark)
                }
            }
        }
        .retroSheet(isPresented: $showAdd) {
            ClockCityPicker { id in store.add(id) }
        }
    }
}

struct ClockWorldRow: View {
    var identifier: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let tz = TimeZone(identifier: identifier) ?? TimeZone.current
            HStack(spacing: 14) {
                ClockWorldFace(date: context.date, timeZone: tz, diameter: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(WorldCityNames.name(identifier))
                        .font(.retro(20, .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 0, y: -1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(WorldCityNames.dayAndOffset(context.date, tz))
                        .font(.retro(13))
                        .foregroundStyle(Color(hex: 0xA0A0A0))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(WorldCityNames.time(context.date, in: tz))
                    .font(.retro(15, .bold))
                    .foregroundStyle(Color(hex: 0xC8C8C8))
                    .lineLimit(1)
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Analog face for a time zone: white by day, black at night (6 PM – 6 AM), as in iOS 4.
struct ClockWorldFace: View {
    var date: Date
    var timeZone: TimeZone
    var diameter: CGFloat

    var body: some View {
        let p = parts
        let d = diameter
        let ink = p.night ? Color.white : Color(hex: 0x111111)
        let red = Color(hex: 0xD8261A)
        ZStack {
            Circle().fill(p.night
                          ? LinearGradient(colors: [Color(hex: 0x3A3A3A), Color(hex: 0x050505)], startPoint: .top, endPoint: .bottom)
                          : LinearGradient(colors: [Color.white, Color(hex: 0xDADADA)], startPoint: .top, endPoint: .bottom))
            Circle().stroke(LinearGradient(colors: [Color(hex: 0xD0D0D0), Color(hex: 0x5A5A5A)], startPoint: .top, endPoint: .bottom),
                            lineWidth: d * 0.04)
            ForEach(1...12, id: \.self) { i in
                let angle = Double(i) * .pi / 6
                Text(verbatim: "\(i)")
                    .font(.retroFixed(d * 0.14, .bold))
                    .foregroundStyle(ink)
                    .offset(x: CGFloat(sin(angle)) * d * 0.35, y: -CGFloat(cos(angle)) * d * 0.35)
            }
            hand(width: d * 0.055, length: d * 0.27, angle: (p.h + p.m / 60) * 30, color: ink)
            hand(width: d * 0.04, length: d * 0.38, angle: (p.m + p.s / 60) * 6, color: ink)
            hand(width: d * 0.018, length: d * 0.42, angle: p.s * 6, color: red)
            Circle().fill(red).frame(width: d * 0.07, height: d * 0.07)
        }
        .frame(width: d, height: d)
        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
        .accessibilityHidden(true)
    }

    private var parts: (h: Double, m: Double, s: Double, night: Bool) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        let hour = c.hour ?? 0
        return (Double(hour % 12), Double(c.minute ?? 0), Double(c.second ?? 0), hour < 6 || hour >= 18)
    }

    private func hand(width: CGFloat, length: CGFloat, angle: Double, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2 + width)
            .rotationEffect(.degrees(angle))
    }
}

// MARK: - City picker

struct ClockCityPicker: View {
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private static let identifiers: [String] = TimeZone.knownTimeZoneIdentifiers
        .filter { $0.contains("/") && !$0.hasPrefix("Etc/") && !$0.hasPrefix("SystemV/") }

    private struct CityEntry: Identifiable {
        let id: String
        let name: String
    }

    private var entries: [CityEntry] {
        let all = Self.identifiers.map { CityEntry(id: $0, name: WorldCityNames.name($0)) }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = q.isEmpty ? all : all.filter { entry in
            entry.name.localizedCaseInsensitiveContains(q)
                || WorldCityNames.englishName(entry.id).localizedCaseInsensitiveContains(q)
                || WorldCityNames.region(entry.id).localizedCaseInsensitiveContains(q)
        }
        let locale = Localizer.shared.language.locale
        return filtered.sorted { a, b in
            a.name.compare(b.name, options: [.caseInsensitive], range: nil, locale: locale) == .orderedAscending
        }
    }

    var body: some View {
        let list = entries
        NavigationStack {
            ClassicPage(title: L("도시 선택"), background: AnyView(Color.white), leading: { EmptyView() }, trailing: {
                ClassicBarButton(title: L("취소")) { dismiss() }
            }) {
                VStack(spacing: 0) {
                    RetroSearchBar(text: $query, placeholder: L("도시 또는 지역 검색"))
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(list) { entry in
                                Button {
                                    Haptics.selection()
                                    onPick(entry.id)
                                    dismiss()
                                } label: {
                                    PlainRow {
                                        HStack(spacing: 6) {
                                            Text(entry.name)
                                                .font(.retro(17, .bold))
                                                .foregroundStyle(.black)
                                                .lineLimit(1)
                                            Text(WorldCityNames.region(entry.id))
                                                .font(.retro(13))
                                                .foregroundStyle(Color(hex: 0x8A8A8A))
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
            }
        }
    }
}
