import SwiftUI
import EventKit

struct CalendarWidget: View {
    var size: WidgetSize
    var frame: CGSize
    @State private var month = Date()
    @Environment(AppRouter.self) private var router

    var body: some View {
        let service = CalendarService.shared
        let _ = service.revision
        let today = ClockTicker.shared.now
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 0) {
                MiniMonthGrid(month: month, today: today, eventDays: service.daysWithEvents(inMonthOf: month),
                              compact: size == .small)
                    .frame(width: size == .wide ? frame.width * 0.55 : nil)
                if size == .wide { eventsList(limit: 3).frame(maxWidth: .infinity) }
            }
            if size == .large { eventsList(limit: 4) }
        }
        .background(LinearGradient(colors: [Color(hex: 0x3A3C40), Color(hex: 0x1E1F22)], startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xEE5A4C), Color(hex: 0xB3150D)], startPoint: .top, endPoint: .bottom)
            WidgetGloss(strength: 0.3)
            HStack {
                arrow("chevron.left", L("이전 달"), -1)
                Spacer()
                EmbossedText(text: RetroFormat.date(month, template: size == .small ? "MMM" : "yMMMM"), size: size == .small ? 14 : 15)
                Spacer()
                arrow("chevron.right", L("다음 달"), 1)
            }
            .padding(.horizontal, 2)
        }
        .frame(height: size == .small ? 26 : 30)
    }

    private func arrow(_ symbol: String, _ label: String, _ delta: Int) -> some View {
        Button {
            Haptics.selection()
            month = Calendar.current.date(byAdding: .month, value: delta, to: month) ?? month
        } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func eventsList(limit: Int) -> some View {
        let service = CalendarService.shared
        VStack(alignment: .leading, spacing: 4) {
            if !service.hasFullAccess {
                Text(service.isDenied ? L("캘린더 접근이 거부되었습니다") : L("일정을 보려면 캘린더를 열어 접근을 허용하세요"))
                    .font(.retroFixed(11)).foregroundStyle(Color(hex: 0xB0B4BC))
            } else {
                let events = service.events(from: Calendar.current.startOfDay(for: Date()),
                                            to: Date().addingTimeInterval(7 * 86400)).prefix(limit)
                if events.isEmpty {
                    Text(L("예정된 일정 없음")).font(.retroFixed(12)).foregroundStyle(Color(hex: 0xB0B4BC))
                }
                ForEach(Array(events), id: \.eventIdentifier) { e in
                    HStack(spacing: 5) {
                        Circle().fill(Color(cgColor: e.calendar.cgColor)).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(e.title ?? "").font(.retroFixed(12, .bold)).foregroundStyle(.white).lineLimit(1)
                            Text(e.isAllDay ? L("하루 종일") : RetroFormat.date(e.startDate, template: "MMMd jm"))
                                .font(.retroFixed(10)).foregroundStyle(Color(hex: 0x9EC0FF))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MiniMonthGrid: View {
    var month: Date
    var today: Date
    var eventDays: Set<Date>
    var compact: Bool

    var body: some View {
        let cal = Calendar.current
        let days = MonthGrid.days(for: month)
        let fontSize: CGFloat = compact ? 9 : 11
        VStack(spacing: 1) {
            HStack(spacing: 0) {
                ForEach(Array(MonthGrid.weekdaySymbols().enumerated()), id: \.offset) { _, s in
                    Text(s).font(.retroFixed(fontSize - 1, .bold)).foregroundStyle(Color(hex: 0xB8BCC4)).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 1) {
                ForEach(days, id: \.self) { day in
                    let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
                    let isToday = cal.isDate(day, inSameDayAs: today)
                    ZStack {
                        if isToday {
                            Circle().fill(Color.white).frame(width: fontSize * 1.8, height: fontSize * 1.8)
                        }
                        Text("\(cal.component(.day, from: day))")
                            .font(.retroFixed(fontSize, .bold))
                            .foregroundStyle(isToday ? Color(hex: 0x111111) : (inMonth ? Color(hex: 0xF2F2F2) : .clear))
                        if eventDays.contains(cal.startOfDay(for: day)) && inMonth {
                            Circle().fill(Color(hex: 0xFF5A4C)).frame(width: 3, height: 3).offset(y: fontSize * 0.85)
                        }
                    }
                    .frame(height: compact ? 13 : 17)
                    .accessibilityHidden(!inMonth)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }
}
