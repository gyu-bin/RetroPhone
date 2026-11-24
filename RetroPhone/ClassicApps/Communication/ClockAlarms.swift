import SwiftUI
import Observation
import UserNotifications

// MARK: - Model & store

nonisolated struct ClockAlarm: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int
    /// Calendar weekdays (1 = Sunday … 7 = Saturday). Empty = one-shot.
    var weekdays: [Int] = []
    var label: String = ""
    var enabled: Bool = true
    /// For one-shot alarms: when the scheduled notification fires (used to switch it off afterwards).
    var oneShotFireDate: Date?
}

/// Alarms persisted locally; each enabled alarm is scheduled as real local notifications.
@Observable
final class ClockAlarmStore {
    static let shared = ClockAlarmStore()
    private static let file = "clock_alarms.json"

    private(set) var alarms: [ClockAlarm]

    private init() {
        alarms = FileStore.load([ClockAlarm].self, from: Self.file) ?? []
        sortAlarms()
    }

    private func sortAlarms() {
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    private func persist() { FileStore.save(alarms, to: Self.file) }

    /// Insert or update, then (re)schedule. Returns false if notifications are not allowed.
    @discardableResult
    func save(_ alarm: ClockAlarm) async -> Bool {
        var updated = alarm
        let ok = await schedule(&updated)
        if !ok { updated.enabled = false }
        if let i = alarms.firstIndex(where: { $0.id == updated.id }) {
            alarms[i] = updated
        } else {
            alarms.append(updated)
        }
        sortAlarms()
        persist()
        return ok
    }

    @discardableResult
    func setEnabled(_ id: UUID, _ enabled: Bool) async -> Bool {
        guard var alarm = alarms.first(where: { $0.id == id }) else { return false }
        alarm.enabled = enabled
        return await save(alarm)
    }

    func delete(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.identifiers(for: id))
        alarms.removeAll { $0.id == id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { alarms[$0].id }
        for id in ids { delete(id) }
    }

    /// Switches off one-shot alarms that have already fired (like the iOS Clock app).
    func refreshExpired() {
        let now = Date().addingTimeInterval(1)
        var changed = false
        for i in alarms.indices where alarms[i].enabled && alarms[i].weekdays.isEmpty {
            if let fire = alarms[i].oneShotFireDate, fire <= now {
                alarms[i].enabled = false
                alarms[i].oneShotFireDate = nil
                changed = true
            }
        }
        if changed { persist() }
    }

    /// Re-adds missing notification requests for enabled repeating alarms (e.g. after a restore).
    func resync() async {
        refreshExpired()
        guard await ClockNotifications.status() == .authorized else { return }
        let pending = Set(await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier))
        for alarm in alarms where alarm.enabled {
            let ids = alarm.weekdays.isEmpty
                ? [Self.oneShotID(alarm.id)]
                : alarm.weekdays.map { Self.repeatingID(alarm.id, $0) }
            if !ids.allSatisfy({ pending.contains($0) }) {
                await save(alarm)
            }
        }
    }

    // MARK: Scheduling

    static func oneShotID(_ id: UUID) -> String { ClockNotificationIDs.alarmPrefix + id.uuidString }
    static func repeatingID(_ id: UUID, _ weekday: Int) -> String { ClockNotificationIDs.alarmPrefix + id.uuidString + "." + String(weekday) }
    static func identifiers(for id: UUID) -> [String] { [oneShotID(id)] + (1...7).map { repeatingID(id, $0) } }

    private func makeContent(_ alarm: ClockAlarm) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? L("알람") : alarm.label
        content.body = ClockAlarmFormat.time(hour: alarm.hour, minute: alarm.minute)
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = ClockNotificationIDs.alarmCategory
        return content
    }

    private func schedule(_ alarm: inout ClockAlarm) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.identifiers(for: alarm.id))
        alarm.oneShotFireDate = nil
        guard alarm.enabled else { return true }
        guard await ClockNotifications.ensureAuthorized() else { return false }

        if alarm.weekdays.isEmpty {
            var comps = DateComponents()
            comps.hour = alarm.hour
            comps.minute = alarm.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            alarm.oneShotFireDate = trigger.nextTriggerDate()
            let request = UNNotificationRequest(identifier: Self.oneShotID(alarm.id), content: makeContent(alarm), trigger: trigger)
            do { try await center.add(request) } catch { return false }
        } else {
            for weekday in alarm.weekdays.sorted() {
                var comps = DateComponents()
                comps.weekday = weekday
                comps.hour = alarm.hour
                comps.minute = alarm.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let request = UNNotificationRequest(identifier: Self.repeatingID(alarm.id, weekday),
                                                    content: makeContent(alarm), trigger: trigger)
                do { try await center.add(request) } catch { return false }
            }
        }
        return true
    }
}

enum ClockAlarmFormat {
    static func date(hour: Int, minute: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }

    static func time(hour: Int, minute: Int) -> String {
        RetroFormat.time(date(hour: hour, minute: minute))
    }

    /// "6:30" and "AM"/"오전" separately, for the big iOS 4 alarm row.
    static func parts(hour: Int, minute: Int) -> (time: String, period: String?) {
        if SettingsStore.shared.value.use24HourClock {
            return (String(format: "%d:%02d", hour, minute), nil)
        }
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let f = DateFormatter()
        f.locale = Localizer.shared.language.locale
        let symbols = [f.amSymbol ?? "AM", f.pmSymbol ?? "PM"]
        return (String(format: "%d:%02d", h12, minute), hour < 12 ? symbols[0] : symbols[1])
    }

    static func weekdaySymbols(short: Bool) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Localizer.shared.language.locale
        return short ? cal.shortWeekdaySymbols : cal.weekdaySymbols
    }

    static func repeatSummary(_ weekdays: [Int]) -> String {
        let set = Set(weekdays)
        if set.isEmpty { return L("안 함") }
        if set.count == 7 { return L("매일") }
        if set == [2, 3, 4, 5, 6] { return L("주중") }
        if set == [1, 7] { return L("주말") }
        let symbols = weekdaySymbols(short: true)
        // Monday-first order like iOS.
        let order = [2, 3, 4, 5, 6, 7, 1]
        return order.filter { set.contains($0) }.map { symbols[$0 - 1] }.joined(separator: " ")
    }
}

// MARK: - Alarm list

struct ClockAlarmListView: View {
    @State private var editMode: EditMode = .inactive
    @State private var editorAlarm: ClockAlarm? = nil
    @State private var notificationsDenied = false

    private var store: ClockAlarmStore { ClockAlarmStore.shared }

    var body: some View {
        NavigationStack {
            ClassicPage(title: L("알람"), leading: {
                if !store.alarms.isEmpty {
                    ClassicBarButton(title: editMode.isEditing ? L("완료") : L("편집"),
                                     kind: editMode.isEditing ? .done : .plain) {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
            }, trailing: {
                ClassicBarButton(title: L("추가"), systemImage: "plus") {
                    let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
                    editorAlarm = ClockAlarm(hour: now.hour ?? 7, minute: now.minute ?? 0)
                }
            }) {
                VStack(spacing: 0) {
                    if store.alarms.isEmpty {
                        Spacer()
                        Text(L("알람 없음"))
                            .font(.retro(20, .bold))
                            .foregroundStyle(Color(hex: 0x4C566C))
                            .embossed()
                        Spacer()
                    } else {
                        List {
                            ForEach(store.alarms) { alarm in
                                alarmRow(alarm)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 10))
                                    .listRowBackground(Color.white)
                            }
                            .onDelete { store.delete(at: $0) }
                        }
                        .listStyle(.plain)
                        .environment(\.editMode, $editMode)
                    }
                    CommNote(text: L("알람은 iOS 알림으로 울립니다. 무음 모드나 집중 모드에서는 소리가 나지 않을 수 있으며, RetroPhone은 기본 시계 앱의 알람을 제어하지 않습니다."))
                }
            }
        }
        .retroSheet(item: $editorAlarm) { alarm in
            ClockAlarmEditor(alarm: alarm, isNew: !store.alarms.contains(where: { $0.id == alarm.id })) { saved in
                if let saved {
                    Task {
                        if !(await store.save(saved)) && saved.enabled { notificationsDenied = true }
                    }
                }
            } onDelete: { id in
                store.delete(id)
            }
        }
        .retroAlert(L("알림이 꺼져 있음"), isPresented: $notificationsDenied,
                    message: L("알람을 울리려면 iOS 설정 > RetroPhone에서 알림을 허용하세요."),
                    buttons: [
                        RetroAlertButton(title: L("닫기")),
                        RetroAlertButton(title: L("설정"), isPreferred: true) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        },
                    ])
        .task { await store.resync() }
    }

    private func alarmRow(_ alarm: ClockAlarm) -> some View {
        let parts = ClockAlarmFormat.parts(hour: alarm.hour, minute: alarm.minute)
        let subtitle = [alarm.label.isEmpty ? L("알람") : alarm.label,
                        alarm.weekdays.isEmpty ? nil : ClockAlarmFormat.repeatSummary(alarm.weekdays)]
            .compactMap { $0 }
            .joined(separator: ", ")
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(parts.time)
                        .font(.retroFixed(38, .bold))
                    if let period = parts.period {
                        Text(period).font(.retroFixed(15, .bold))
                    }
                }
                .foregroundStyle(alarm.enabled ? Color.black : Color(hex: 0x8A8A8A))
                Text(subtitle)
                    .font(.retro(13))
                    .foregroundStyle(Color(hex: 0x6A6A6A))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !editMode.isEditing {
                RetroToggle(isOn: Binding(get: { alarm.enabled }, set: { newValue in
                    Task {
                        if !(await store.setEnabled(alarm.id, newValue)) && newValue { notificationsDenied = true }
                    }
                }), label: L("알람"))
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if editMode.isEditing { editorAlarm = alarm }
        }
    }
}

// MARK: - Alarm editor

struct ClockAlarmEditor: View {
    var isNew: Bool
    var onSave: (ClockAlarm?) -> Void
    var onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ClockAlarm
    @State private var time: Date

    init(alarm: ClockAlarm, isNew: Bool, onSave: @escaping (ClockAlarm?) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: alarm)
        _time = State(initialValue: ClockAlarmFormat.date(hour: alarm.hour, minute: alarm.minute))
    }

    var body: some View {
        NavigationStack {
            ClassicPage(title: isNew ? L("알람 추가") : L("알람 편집"), leading: {
                ClassicBarButton(title: L("취소")) {
                    onSave(nil)
                    dismiss()
                }
            }, trailing: {
                ClassicBarButton(title: L("저장"), kind: .done) {
                    var result = draft
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
                    result.hour = comps.hour ?? 0
                    result.minute = comps.minute ?? 0
                    result.label = result.label.trimmingCharacters(in: .whitespacesAndNewlines)
                    result.enabled = true
                    onSave(result)
                    dismiss()
                }
            }) {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            GroupedSection {
                                NavigationLink {
                                    ClockRepeatPicker(weekdays: $draft.weekdays)
                                } label: {
                                    TableRow(title: L("반복"), detail: ClockAlarmFormat.repeatSummary(draft.weekdays), chevron: true)
                                }
                                .buttonStyle(.plain)
                                TableRow(title: L("레이블")) {
                                    TextField(L("알람"), text: $draft.label)
                                        .font(.retro(17))
                                        .multilineTextAlignment(.trailing)
                                        .foregroundStyle(Color(hex: 0x385487))
                                        .submitLabel(.done)
                                }
                                TableRow(title: L("사운드"), detail: L("iOS 기본 알림음"))
                            }
                            CommNote(text: L("알람은 iOS 알림으로 전달됩니다. 다시 알림(스누즈)은 지원하지 않습니다."))
                            if !isNew {
                                GlossyButton(title: L("알람 삭제"), tint: .red) {
                                    onDelete(draft.id)
                                    dismiss()
                                }
                                .padding(.horizontal, 10)
                                .padding(.top, 6)
                            }
                        }
                        .padding(.bottom, 10)
                    }
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .environment(\.locale, SettingsStore.shared.value.use24HourClock
                                     ? Locale(identifier: "en_GB") : Localizer.shared.language.locale)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(colors: [Color(hex: 0x2B2B2F), Color(hex: 0x4A4C55)], startPoint: .top, endPoint: .bottom)
                        )
                        .environment(\.colorScheme, .dark)
                }
            }
        }
    }
}

struct ClockRepeatPicker: View {
    @Binding var weekdays: [Int]
    @Environment(\.retroTheme) private var theme

    var body: some View {
        let symbols = ClockAlarmFormat.weekdaySymbols(short: false)
        ClassicPage(title: L("반복"), leading: { ClassicBackButton() }, trailing: { EmptyView() }) {
            ScrollView {
                GroupedSection {
                    ForEach([1, 2, 3, 4, 5, 6, 7], id: \.self) { day in
                        Button {
                            Haptics.selection()
                            if let i = weekdays.firstIndex(of: day) { weekdays.remove(at: i) } else { weekdays.append(day) }
                        } label: {
                            TableRow(title: LF("%@마다", symbols[day - 1])) {
                                if weekdays.contains(day) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(theme.detailText)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
