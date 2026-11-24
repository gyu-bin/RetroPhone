import SwiftUI
import EventKit

/// iOS 4 Calendar with real EventKit data: month grid, list and day modes, add/edit via EventKitUI.
struct CalendarAppView: View {
    enum Mode: Hashable { case list, day, month }

    @Environment(AppRouter.self) private var router
    @State private var mode: Mode = .month
    @State private var selected = Calendar.current.startOfDay(for: Date())
    @State private var month = Date()
    @State private var path: [CalAppEventRoute] = []
    @State private var editing: CalAppEditRequest? = nil
    @State private var showCalendars = false
    @State private var hidden: Set<String> = CalAppStorage.loadHidden()

    private var service: CalendarService { CalendarService.shared }

    var body: some View {
        NavigationStack(path: $path) {
            ClassicPage(title: L("캘린더"), leading: {
                if service.hasFullAccess {
                    ClassicBarButton(title: L("캘린더")) { showCalendars = true }
                }
            }, trailing: {
                if service.hasFullAccess {
                    ClassicBarButton(title: L("추가"), systemImage: "plus") {
                        editing = CalAppEditRequest(event: nil, start: defaultStart())
                    }
                }
            }) {
                content
            }
            .navigationDestination(for: CalAppEventRoute.self) { route in
                CalAppEventDetailView(event: route.event)
            }
        }
        .sheet(item: $editing) { request in
            CalAppEventEditor(event: request.event, defaultStart: request.start) { _ in
                editing = nil
            }
            .ignoresSafeArea()
        }
        .retroSheet(isPresented: $showCalendars) {
            CalAppVisibilitySheet(hidden: $hidden)
        }
        .onChange(of: hidden) { _, newValue in
            CalAppStorage.saveHidden(newValue)
        }
        .onChange(of: router.pendingDeepLink, initial: true) { _, link in
            if case .calendar(let date)? = link {
                selected = Calendar.current.startOfDay(for: date)
                month = date
                mode = .month
                path = []
                router.pendingDeepLink = nil
            }
        }
        .task {
            // First use: ask for full calendar access right away.
            if service.status == .notDetermined {
                await service.requestAccess()
            }
        }
    }

    @ViewBuilder private var content: some View {
        if service.hasFullAccess {
            VStack(spacing: 0) {
                Group {
                    switch mode {
                    case .month:
                        CalAppMonthView(month: $month, selected: $selected, hidden: hidden, onOpen: open)
                    case .list:
                        CalAppListView(anchor: selected, hidden: hidden, onOpen: open)
                    case .day:
                        CalAppDayView(selected: $selected, hidden: hidden, onOpen: open)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                ClassicToolbar {
                    ClassicBarButton(title: L("오늘")) { goToday() }
                    Spacer(minLength: 6)
                    RetroSegmented(options: [(Mode.list, L("목록")), (Mode.day, L("일")), (Mode.month, L("월"))],
                                   selection: $mode)
                        .frame(maxWidth: 190)
                    Spacer(minLength: 6)
                    Color.clear.frame(width: 50, height: 1)
                }
            }
        } else if service.isDenied {
            PermissionPlaceholder(systemImage: "calendar.badge.exclamationmark",
                                  title: L("캘린더 접근이 거부됨"),
                                  message: L("일정을 보고 편집하려면 iOS 설정 > RetroPhone에서 캘린더 전체 접근을 허용하세요."),
                                  denied: true)
        } else {
            PermissionPlaceholder(systemImage: "calendar",
                                  title: L("캘린더 접근"),
                                  message: L("기기의 캘린더 일정을 표시하고 편집하려면 접근을 허용하세요."),
                                  requestTitle: L("접근 허용"),
                                  request: { Task { await service.requestAccess() } })
        }
    }

    private func open(_ event: EKEvent) {
        path.append(CalAppEventRoute(event: event))
    }

    private func goToday() {
        let today = Calendar.current.startOfDay(for: Date())
        withAnimation(.easeOut(duration: 0.2)) {
            selected = today
            month = today
        }
    }

    private func defaultStart() -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: selected)
        comps.hour = min(23, cal.component(.hour, from: Date()) + 1)
        comps.minute = 0
        return cal.date(from: comps) ?? selected
    }
}

// MARK: - Helpers

nonisolated struct CalAppEventRoute: Hashable {
    let event: EKEvent
    static func == (a: CalAppEventRoute, b: CalAppEventRoute) -> Bool { a.event === b.event }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(event)) }
}

struct CalAppEditRequest: Identifiable {
    let id = UUID()
    var event: EKEvent?
    var start: Date?
}

enum CalAppStorage {
    static let hiddenFile = "calendar_hidden.json"
    static func loadHidden() -> Set<String> { Set(FileStore.load([String].self, from: hiddenFile) ?? []) }
    static func saveHidden(_ ids: Set<String>) { FileStore.save(Array(ids).sorted(), to: hiddenFile) }
}

enum CalAppEvents {
    static func events(from start: Date, to end: Date, hidden: Set<String>) -> [EKEvent] {
        CalendarService.shared.events(from: start, to: end).filter { event in
            guard let id = event.calendar?.calendarIdentifier else { return true }
            return !hidden.contains(id)
        }
    }

    /// Events touching `day`, all-day events first.
    static func events(on day: Date, hidden: Set<String>) -> [EKEvent] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let list = events(from: start, to: end, hidden: hidden)
        return list.filter { $0.isAllDay } + list.filter { !$0.isAllDay }
    }

    /// Day-start dates in the month covered by at least one (visible) event, including multi-day spans.
    static func markedDays(inMonthOf month: Date, hidden: Set<String>) -> Set<Date> {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        var out = Set<Date>()
        for event in events(from: interval.start, to: interval.end, hidden: hidden) {
            let eventStart: Date = event.startDate
            let eventEnd: Date = event.endDate
            var day = cal.startOfDay(for: max(eventStart, interval.start))
            let end = min(eventEnd, interval.end)
            var steps = 0
            repeat {
                out.insert(day)
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                steps += 1
            } while day < end && steps < 32
        }
        return out
    }

    static func color(_ event: EKEvent) -> Color {
        if let cg = event.calendar?.cgColor { return Color(cgColor: cg) }
        return Color(hex: 0x2F6BDB)
    }
}

// MARK: - Shared header (silver bar with month/day title and arrows)

struct CalAppHeader: View {
    var title: String
    var showWeekdays: Bool
    var onPrev: () -> Void
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                arrow("arrowtriangle.left.fill", L("이전"), onPrev)
                Spacer()
                Text(title)
                    .font(.retro(20, .bold))
                    .foregroundStyle(Color(hex: 0x3A404C))
                    .embossed(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                arrow("arrowtriangle.right.fill", L("다음"), onNext)
            }
            .frame(height: 40)
            if showWeekdays {
                HStack(spacing: 0) {
                    ForEach(Array(MonthGrid.weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.retroFixed(10, .bold))
                            .foregroundStyle(Color(hex: 0x4A505C))
                            .embossed(.white.opacity(0.9))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 16)
            }
        }
        .background(
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(hex: 0xF6F6F8), Color(hex: 0xCDD0D7)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color(hex: 0x8E939C)).frame(height: 1)
            }
        )
    }

    private func arrow(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            SoundService.shared.play(.tock)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: 0x5A6170))
                .shadow(color: .white, radius: 0, y: 1)
                .frame(width: 50, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Month mode

struct CalAppMonthView: View {
    @Binding var month: Date
    @Binding var selected: Date
    var hidden: Set<String>
    var onOpen: (EKEvent) -> Void

    var body: some View {
        let _ = CalendarService.shared.revision
        let cal = Calendar.current
        let marked = CalAppEvents.markedDays(inMonthOf: month, hidden: hidden)
        let weeks = self.weeks(cal)
        let today = cal.startOfDay(for: ClockTicker.shared.now)
        let cellHeight: CGFloat = weeks.count >= 6 ? 40 : 44
        VStack(spacing: 0) {
            CalAppHeader(title: RetroFormat.date(month, template: "yMMMM"), showWeekdays: true,
                         onPrev: { shift(-1) }, onNext: { shift(1) })
            VStack(spacing: 0) {
                ForEach(weeks.indices, id: \.self) { w in
                    HStack(spacing: 0) {
                        ForEach(weeks[w], id: \.self) { day in
                            dayCell(day,
                                    inMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                                    isToday: cal.isDate(day, inSameDayAs: today),
                                    isSelected: cal.isDate(day, inSameDayAs: selected),
                                    hasEvents: marked.contains(cal.startOfDay(for: day)))
                                .frame(height: cellHeight)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 25).onEnded { value in
                    if value.translation.width < -50 { shift(1) } else if value.translation.width > 50 { shift(-1) }
                }
            )
            Rectangle().fill(Color(hex: 0x8E939C)).frame(height: 1)
            CalAppDayEventList(day: selected, hidden: hidden, onOpen: onOpen)
        }
    }

    private func weeks(_ cal: Calendar) -> [[Date]] {
        let days = MonthGrid.days(for: month, calendar: cal)
        var rows: [[Date]] = []
        var index = 0
        while index + 7 <= days.count {
            let row = Array(days[index..<(index + 7)])
            if row.contains(where: { cal.isDate($0, equalTo: month, toGranularity: .month) }) { rows.append(row) }
            index += 7
        }
        return rows
    }

    private func shift(_ delta: Int) {
        let cal = Calendar.current
        guard let newMonth = cal.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            month = newMonth
            // Keep the selection inside the visible month (first day, or today if it's this month).
            if cal.isDate(Date(), equalTo: newMonth, toGranularity: .month) {
                selected = cal.startOfDay(for: Date())
            } else if let first = cal.dateInterval(of: .month, for: newMonth)?.start {
                selected = first
            }
        }
    }

    private func cellColors(inMonth: Bool, isToday: Bool, isSelected: Bool) -> [Color] {
        if isSelected { return [Color(hex: 0x6FA0F5), Color(hex: 0x2559D0)] }
        if isToday { return [Color(hex: 0x91A5C4), Color(hex: 0x6A7FA3)] }
        if inMonth { return [Color(hex: 0xF3F4F6), Color(hex: 0xDDE0E5)] }
        return [Color(hex: 0xD8DADF), Color(hex: 0xC8CBD1)]
    }

    private func dayCell(_ day: Date, inMonth: Bool, isToday: Bool, isSelected: Bool, hasEvents: Bool) -> some View {
        let cal = Calendar.current
        let highlighted = isSelected || isToday
        let colors = cellColors(inMonth: inMonth, isToday: isToday, isSelected: isSelected)
        return Button {
            Haptics.selection()
            withAnimation(.easeOut(duration: 0.15)) {
                selected = cal.startOfDay(for: day)
                if !inMonth { month = day }
            }
        } label: {
            ZStack {
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                VStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(highlighted ? 0.25 : 0.8)).frame(height: 1)
                    Spacer(minLength: 0)
                    Rectangle().fill(Color(hex: 0xA3A7AF)).frame(height: 1)
                }
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle().fill(Color(hex: 0xA3A7AF)).frame(width: 1)
                }
                Text(verbatim: "\(cal.component(.day, from: day))")
                    .font(.retroFixed(20, .bold))
                    .foregroundStyle(highlighted ? Color.white : (inMonth ? Color(hex: 0x2A2E36) : Color(hex: 0x8E939D)))
                    .shadow(color: highlighted ? .black.opacity(0.4) : .white.opacity(0.9), radius: 0, y: highlighted ? -1 : 1)
                if hasEvents {
                    Circle()
                        .fill(highlighted ? Color.white : Color(hex: 0x3D4554))
                        .frame(width: 5, height: 5)
                        .offset(y: 13)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(RetroFormat.date(day, template: "MMMMdEEEE"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// White list of the selected day's events under the month grid.
struct CalAppDayEventList: View {
    var day: Date
    var hidden: Set<String>
    var onOpen: (EKEvent) -> Void

    var body: some View {
        let _ = CalendarService.shared.revision
        let events = CalAppEvents.events(on: day, hidden: hidden)
        ScrollView {
            LazyVStack(spacing: 0) {
                if events.isEmpty {
                    Text(L("일정 없음"))
                        .font(.retro(15))
                        .foregroundStyle(Color(hex: 0x9A9A9A))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    Button { onOpen(event) } label: {
                        CalAppEventRow(event: event, day: day)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color.white)
    }
}

struct CalAppEventRow: View {
    var event: EKEvent
    var day: Date

    var body: some View {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let start: Date = event.startDate
        let end: Date = event.endDate
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    if event.isAllDay {
                        Text(L("하루 종일")).font(.retro(12, .bold)).foregroundStyle(.black)
                    } else {
                        Text(start < dayStart ? L("계속") : RetroFormat.time(start))
                            .font(.retro(12, .bold)).foregroundStyle(.black)
                        if end <= dayEnd {
                            Text(RetroFormat.time(end)).font(.retro(11)).foregroundStyle(Color(hex: 0x8A8A8A))
                        }
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 68, alignment: .trailing)
                Circle().fill(CalAppEvents.color(event)).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title ?? "")
                        .font(.retro(16, .bold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(.retro(13))
                            .foregroundStyle(Color(hex: 0x8A8A8A))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 46)
            Rectangle().fill(Color(hex: 0xE0E0E0)).frame(height: 1)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - List mode

struct CalAppListView: View {
    var anchor: Date
    var hidden: Set<String>
    var onOpen: (EKEvent) -> Void

    private struct DayGroup: Identifiable {
        var day: Date
        var events: [EKEvent]
        var id: Date { day }
    }

    var body: some View {
        let _ = CalendarService.shared.revision
        let groups = self.groups()
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                if groups.isEmpty {
                    Text(L("앞으로 90일 동안 일정 없음"))
                        .font(.retro(15))
                        .foregroundStyle(Color(hex: 0x9A9A9A))
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                ForEach(groups) { group in
                    SwiftUI.Section {
                        ForEach(Array(group.events.enumerated()), id: \.offset) { _, event in
                            Button { onOpen(event) } label: {
                                CalAppEventRow(event: event, day: group.day)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        PlainSectionHeader(title: RetroFormat.date(group.day, template: "yMMMdEEE"))
                    }
                }
            }
        }
        .background(Color.white)
    }

    private func groups() -> [DayGroup] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: anchor)
        guard let end = cal.date(byAdding: .day, value: 90, to: start) else { return [] }
        let events = CalAppEvents.events(from: start, to: end, hidden: hidden)
        let grouped = Dictionary(grouping: events) { event -> Date in
            let s: Date = event.startDate
            return cal.startOfDay(for: max(s, start))
        }
        return grouped.keys.sorted().map { day in
            let list = grouped[day] ?? []
            return DayGroup(day: day, events: list.filter { $0.isAllDay } + list.filter { !$0.isAllDay })
        }
    }
}

// MARK: - Day mode

struct CalAppDayView: View {
    @Binding var selected: Date
    var hidden: Set<String>
    var onOpen: (EKEvent) -> Void

    private let hourHeight: CGFloat = 44
    private let labelWidth: CGFloat = 56
    private let topInset: CGFloat = 8

    private struct Block {
        var event: EKEvent
        var start: Double
        var end: Double
        var column: Int
        var columns: Int
    }

    var body: some View {
        let _ = CalendarService.shared.revision
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: selected)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let events = CalAppEvents.events(on: selected, hidden: hidden)
        let allDay = events.filter { e in
            let s: Date = e.startDate
            let en: Date = e.endDate
            return e.isAllDay || (s <= dayStart && en >= dayEnd)
        }
        let timed = events.filter { e in !allDay.contains(where: { $0 === e }) }
        let blocks = layout(timed, dayStart: dayStart)
        VStack(spacing: 0) {
            CalAppHeader(title: RetroFormat.date(selected, template: "yMMMMdEEEE"), showWeekdays: false,
                         onPrev: { shiftDay(-1) }, onNext: { shiftDay(1) })
            if !allDay.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(allDay.enumerated()), id: \.offset) { _, event in
                        Button { onOpen(event) } label: {
                            HStack(spacing: 6) {
                                Text(L("하루 종일"))
                                    .font(.retro(11, .bold))
                                    .foregroundStyle(Color(hex: 0x4A505C))
                                    .frame(width: labelWidth - 6, alignment: .trailing)
                                Text(event.title ?? "")
                                    .font(.retro(13, .bold))
                                    .foregroundStyle(.black)
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                                    .background(CalAppEvents.color(event).opacity(0.3))
                                    .overlay(alignment: .leading) {
                                        Rectangle().fill(CalAppEvents.color(event)).frame(width: 3)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .padding(.trailing, 6)
                .background(Color(hex: 0xE8EAEE))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        hourGrid
                        GeometryReader { geo in
                            let columnArea = max(40, geo.size.width - labelWidth - 10)
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                eventBlock(block, width: columnArea)
                            }
                        }
                        if cal.isDateInToday(selected) {
                            nowLine(dayStart: dayStart)
                        }
                    }
                    .frame(height: hourHeight * 24 + topInset * 2)
                }
                .background(Color.white)
                .onAppear { scrollToInitialHour(proxy, blocks: blocks) }
                .onChange(of: selected) { scrollToInitialHour(proxy, blocks: blocks) }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 40).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < -60 { shiftDay(1) } else if value.translation.width > 60 { shiftDay(-1) }
                }
            )
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0...24, id: \.self) { hour in
                HStack(alignment: .center, spacing: 4) {
                    Text(hourLabel(hour))
                        .font(.retroFixed(11, .bold))
                        .foregroundStyle(Color(hex: 0x6A6E78))
                        .frame(width: labelWidth - 4, alignment: .trailing)
                    Rectangle().fill(Color(hex: 0xD6D8DC)).frame(height: 1)
                }
                .frame(height: topInset * 2)
                .frame(height: hour == 24 ? topInset * 2 : hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    private func nowLine(dayStart: Date) -> some View {
        let minutes = ClockTicker.shared.now.timeIntervalSince(dayStart) / 60
        return HStack(spacing: 0) {
            Circle().fill(Color(hex: 0xD8261A)).frame(width: 7, height: 7)
            Rectangle().fill(Color(hex: 0xD8261A)).frame(height: 1.5)
        }
        .padding(.leading, labelWidth - 3)
        .offset(y: topInset + CGFloat(minutes / 60) * hourHeight - 3.5)
        .allowsHitTesting(false)
    }

    private func eventBlock(_ block: Block, width: CGFloat) -> some View {
        let columnWidth = width / CGFloat(max(1, block.columns))
        let y = topInset + CGFloat(block.start / 60) * hourHeight
        let height = max(20, CGFloat((block.end - block.start) / 60) * hourHeight - 1)
        let color = CalAppEvents.color(block.event)
        return Button { onOpen(block.event) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(block.event.title ?? "")
                    .font(.retro(12, .bold))
                    .foregroundStyle(.black)
                    .lineLimit(height > 34 ? 2 : 1)
                if height > 34, let location = block.event.location, !location.isEmpty {
                    Text(location).font(.retro(11)).foregroundStyle(Color(hex: 0x4A4A4A)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
            .padding(.top, 2)
            .frame(width: columnWidth - 2, height: height, alignment: .topLeading)
            .background(color.opacity(0.28))
            .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .offset(x: labelWidth + 4 + CGFloat(block.column) * columnWidth, y: y)
    }

    private func hourLabel(_ hour: Int) -> String {
        if SettingsStore.shared.value.use24HourClock { return String(format: "%02d:00", hour % 24) }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour % 24
        guard let date = Calendar.current.date(from: comps) else { return "" }
        if hour == 12 { return L("정오") }
        return RetroFormat.date(date, template: "ha")
    }

    private func shiftDay(_ delta: Int) {
        guard let d = Calendar.current.date(byAdding: .day, value: delta, to: selected) else { return }
        Haptics.selection()
        selected = Calendar.current.startOfDay(for: d)
    }

    private func scrollToInitialHour(_ proxy: ScrollViewProxy, blocks: [Block]) {
        let hour: Int
        if Calendar.current.isDateInToday(selected) {
            hour = max(0, Calendar.current.component(.hour, from: Date()) - 1)
        } else if let first = blocks.map(\.start).min() {
            hour = max(0, Int(first / 60) - 1)
        } else {
            hour = 8
        }
        proxy.scrollTo(min(hour, 16), anchor: .top)
    }

    /// Greedy column layout for overlapping events.
    private func layout(_ events: [EKEvent], dayStart: Date) -> [Block] {
        let sorted = events.sorted { a, b in
            let sa: Date = a.startDate
            let sb: Date = b.startDate
            return sa < sb
        }
        var blocks: [Block] = []
        var clusterStart = 0
        var columnEnds: [Double] = []
        var clusterEnd: Double = -1

        func closeCluster() {
            let count = max(1, columnEnds.count)
            var i = clusterStart
            while i < blocks.count {
                blocks[i].columns = count
                i += 1
            }
            clusterStart = blocks.count
            columnEnds = []
            clusterEnd = -1
        }

        for event in sorted {
            let eventStart: Date = event.startDate
            let eventEnd: Date = event.endDate
            let s = min(1440, max(0, eventStart.timeIntervalSince(dayStart) / 60))
            let e = max(s + 20, min(1440, eventEnd.timeIntervalSince(dayStart) / 60))
            if !columnEnds.isEmpty && s >= clusterEnd { closeCluster() }
            let column: Int
            if let free = columnEnds.firstIndex(where: { $0 <= s }) {
                column = free
                columnEnds[free] = e
            } else {
                column = columnEnds.count
                columnEnds.append(e)
            }
            blocks.append(Block(event: event, start: s, end: e, column: column, columns: 1))
            clusterEnd = max(clusterEnd, e)
        }
        closeCluster()
        return blocks
    }
}
