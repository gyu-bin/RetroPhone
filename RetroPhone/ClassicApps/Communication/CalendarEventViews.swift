import SwiftUI
import EventKit
import EventKitUI

// MARK: - Event detail (iOS 4 "Event" page)

struct CalAppEventDetailView: View {
    let event: EKEvent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.retroTheme) private var theme
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var deleteFailed = false
    @State private var cannotOpen = false
    @State private var tick = 0

    private var canModify: Bool { event.calendar?.allowsContentModifications ?? false }

    var body: some View {
        let _ = tick
        ClassicPage(title: L("일정 정보"), leading: { ClassicBackButton() }, trailing: {
            if canModify {
                ClassicBarButton(title: L("편집")) { editing = true }
            }
        }) {
            ScrollView {
                VStack(spacing: 0) {
                    GroupedSection {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(eventTitle)
                                .font(.retro(19, .bold))
                                .foregroundStyle(.black)
                            if let location = event.location, !location.isEmpty {
                                Text(location)
                                    .font(.retro(15))
                                    .foregroundStyle(Color(hex: 0x6A6A6A))
                            }
                            ForEach(timeLines, id: \.self) { line in
                                Text(line)
                                    .font(.retro(14, .bold))
                                    .foregroundStyle(theme.detailText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    if let recurrence = recurrenceText {
                        GroupedSection {
                            TableRow(title: L("반복"), detail: recurrence)
                        }
                    }
                    GroupedSection {
                        TableRow(title: L("캘린더"), detail: event.calendar?.title) {
                            Circle().fill(CalAppEvents.color(event)).frame(width: 10, height: 10)
                        }
                    }
                    let alarms = alarmTexts
                    if !alarms.isEmpty {
                        GroupedSection {
                            ForEach(Array(alarms.enumerated()), id: \.offset) { index, text in
                                TableRow(title: index == 0 ? L("알림") : L("두 번째 알림"), detail: text)
                            }
                        }
                    }
                    if let url = event.url {
                        GroupedSection {
                            Button {
                                Task {
                                    if !(await UIApplication.shared.open(url, options: [:])) { cannotOpen = true }
                                }
                            } label: {
                                CommDetailRow(label: "URL", value: url.absoluteString, valueColor: theme.detailText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let notes = event.notes, !notes.isEmpty {
                        GroupedSection(header: L("메모")) {
                            Text(notes)
                                .font(.retro(15))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .textSelection(.enabled)
                        }
                    }
                    if canModify {
                        GlossyButton(title: L("일정 삭제"), tint: .red) { confirmDelete = true }
                            .padding(.horizontal, 10)
                            .padding(.top, 20)
                    }
                    Color.clear.frame(height: 24)
                }
            }
        }
        .sheet(isPresented: $editing, onDismiss: { tick += 1 }) {
            CalAppEventEditor(event: event, defaultStart: nil) { action in
                editing = false
                if action == .deleted { dismiss() }
            }
            .ignoresSafeArea()
        }
        .commActionSheet(isPresented: $confirmDelete, buttons: deleteButtons)
        .retroAlert(L("삭제할 수 없음"), isPresented: $deleteFailed, message: L("이 일정을 삭제하지 못했습니다."))
        .retroAlert(L("열 수 없음"), isPresented: $cannotOpen)
        .onChange(of: CalendarService.shared.revision) {
            // The store changed (here or elsewhere): refresh, or leave if the event was deleted.
            if event.refresh() { tick += 1 } else { dismiss() }
        }
    }

    private var eventTitle: String {
        let t = event.title ?? ""
        return t.isEmpty ? L("새로운 일정") : t
    }

    private var timeLines: [String] {
        let cal = Calendar.current
        let start: Date = event.startDate
        let end: Date = event.endDate
        if event.isAllDay {
            let lastDay = cal.date(byAdding: .second, value: -1, to: end) ?? end
            if cal.isDate(start, inSameDayAs: lastDay) {
                return [L("하루 종일"), RetroFormat.date(start, template: "yMMMMdEEEE")]
            }
            return [L("하루 종일"),
                    RetroFormat.date(start, template: "yMMMdEEE") + " ~ " + RetroFormat.date(lastDay, template: "yMMMdEEE")]
        }
        if cal.isDate(start, inSameDayAs: end) {
            return [RetroFormat.date(start, template: "yMMMMdEEEE"),
                    RetroFormat.time(start) + " ~ " + RetroFormat.time(end)]
        }
        return [L("시작") + "  " + RetroFormat.date(start, template: "yMMMdEEE") + " " + RetroFormat.time(start),
                L("종료") + "  " + RetroFormat.date(end, template: "yMMMdEEE") + " " + RetroFormat.time(end)]
    }

    private var recurrenceText: String? {
        guard let rule = event.recurrenceRules?.first else { return nil }
        let n = rule.interval
        switch rule.frequency {
        case .daily: return n <= 1 ? L("매일") : LF("%d일마다", n)
        case .weekly: return n <= 1 ? L("매주") : LF("%d주마다", n)
        case .monthly: return n <= 1 ? L("매월") : LF("%d개월마다", n)
        case .yearly: return n <= 1 ? L("매년") : LF("%d년마다", n)
        @unknown default: return L("사용자 설정")
        }
    }

    private var alarmTexts: [String] {
        (event.alarms ?? []).map { alarm in
            if let absolute = alarm.absoluteDate {
                return RetroFormat.date(absolute, template: "yMMMdjmm")
            }
            let minutes = Int((-alarm.relativeOffset / 60).rounded())
            if minutes == 0 { return L("일정 시간") }
            if minutes < 0 { return LF("%d분 후", -minutes) }
            if minutes % 1440 == 0 { return LF("%d일 전", minutes / 1440) }
            if minutes % 60 == 0 { return LF("%d시간 전", minutes / 60) }
            return LF("%d분 전", minutes)
        }
    }

    private var deleteButtons: [CommSheetButton] {
        var buttons: [CommSheetButton] = []
        if event.hasRecurrenceRules {
            buttons.append(CommSheetButton(title: L("이 일정만 삭제"), role: .destructive) { delete(.thisEvent) })
            buttons.append(CommSheetButton(title: L("이후 모든 일정 삭제"), role: .destructive) { delete(.futureEvents) })
        } else {
            buttons.append(CommSheetButton(title: L("일정 삭제"), role: .destructive) { delete(.thisEvent) })
        }
        buttons.append(CommSheetButton(title: L("취소"), role: .cancel))
        return buttons
    }

    private func delete(_ span: EKSpan) {
        do {
            try CalendarService.shared.store.remove(event, span: span, commit: true)
            Haptics.success()
            dismiss()
        } catch {
            deleteFailed = true
        }
    }
}

// MARK: - EKEventEditViewController bridge (add / edit)

struct CalAppEventEditor: UIViewControllerRepresentable {
    /// Existing event to edit, or nil to create a new one.
    var event: EKEvent?
    var defaultStart: Date?
    var onDone: (EKEventEditViewAction) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = CalendarService.shared.store
        let vc = EKEventEditViewController()
        vc.eventStore = store
        if let event {
            vc.event = event
        } else {
            let newEvent = EKEvent(eventStore: store)
            let start = defaultStart ?? Date()
            newEvent.startDate = start
            newEvent.endDate = start.addingTimeInterval(3600)
            newEvent.calendar = store.defaultCalendarForNewEvents
            vc.event = newEvent
        }
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {
        context.coordinator.onDone = onDone
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        var onDone: (EKEventEditViewAction) -> Void

        init(onDone: @escaping (EKEventEditViewAction) -> Void) {
            self.onDone = onDone
        }

        nonisolated func eventEditViewController(_ controller: EKEventEditViewController,
                                                 didCompleteWith action: EKEventEditViewAction) {
            MainActor.assumeIsolated {
                self.onDone(action)
            }
        }
    }
}

// MARK: - Calendars visibility ("Calendars" button)

struct CalAppVisibilitySheet: View {
    @Binding var hidden: Set<String>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.retroTheme) private var theme

    private struct SourceGroup: Identifiable {
        var title: String
        var calendars: [EKCalendar]
        var id: String { title }
    }

    var body: some View {
        let groups = sourceGroups()
        let allIDs = Set(groups.flatMap { $0.calendars.map(\.calendarIdentifier) })
        NavigationStack {
            ClassicPage(title: L("캘린더"), leading: {
                ClassicBarButton(title: hidden.isEmpty ? L("모두 숨기기") : L("모두 보기")) {
                    hidden = hidden.isEmpty ? allIDs : []
                }
            }, trailing: {
                ClassicBarButton(title: L("완료"), kind: .done) { dismiss() }
            }) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(groups) { group in
                            GroupedSection(header: group.title.isEmpty ? nil : group.title) {
                                ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                                    Button {
                                        Haptics.selection()
                                        toggle(calendar.calendarIdentifier)
                                    } label: {
                                        row(calendar)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        CommNote(text: L("숨긴 캘린더의 일정은 RetroPhone 캘린더에만 표시되지 않으며, 실제 캘린더는 변경되지 않습니다."))
                            .padding(.bottom, 20)
                    }
                }
            }
        }
    }

    private func row(_ calendar: EKCalendar) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color(cgColor: calendar.cgColor)).frame(width: 12, height: 12)
            Text(calendar.title)
                .font(.retro(17, .bold))
                .foregroundStyle(.black)
                .lineLimit(1)
            Spacer(minLength: 6)
            if !hidden.contains(calendar.calendarIdentifier) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.detailText)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func toggle(_ id: String) {
        if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
    }

    private func sourceGroups() -> [SourceGroup] {
        let calendars = CalendarService.shared.store.calendars(for: .event)
        let grouped = Dictionary(grouping: calendars) { calendar -> String in
            calendar.source?.title ?? ""
        }
        return grouped.keys.sorted().map { key in
            SourceGroup(title: key,
                        calendars: (grouped[key] ?? []).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
        }
    }
}
