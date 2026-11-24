import EventKit
import Observation
import UIKit

/// EventKit wrapper shared by the Calendar app and the calendar widget.
@Observable
final class CalendarService {
    static let shared = CalendarService()

    let store = EKEventStore()
    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    /// Bumped whenever the event store changes so views can reload.
    private(set) var revision = 0

    var hasFullAccess: Bool { status == .fullAccess }
    var isDenied: Bool { status == .denied || status == .restricted || status == .writeOnly }

    private init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.revision += 1 }
        }
    }

    @discardableResult
    func requestAccess() async -> Bool {
        if hasFullAccess { return true }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        status = EKEventStore.authorizationStatus(for: .event)
        revision += 1
        return granted
    }

    func events(from start: Date, to end: Date) -> [EKEvent] {
        guard hasFullAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func events(on day: Date) -> [EKEvent] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        return events(from: start, to: cal.date(byAdding: .day, value: 1, to: start)!)
    }

    /// Set of day-start dates in the given month that have at least one event.
    func daysWithEvents(inMonthOf date: Date) -> Set<Date> {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: date) else { return [] }
        return Set(events(from: interval.start, to: interval.end).map { cal.startOfDay(for: $0.startDate) })
    }

    func delete(_ event: EKEvent) throws {
        try store.remove(event, span: .thisEvent, commit: true)
    }
}

/// Month grid math shared by the calendar widget and app (unit-tested).
enum MonthGrid {
    /// Returns 42 (6×7) dates covering the month, starting on the calendar's first weekday.
    static func days(for month: Date, calendar: Calendar = .current) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let weekday = calendar.component(.weekday, from: first)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -lead, to: first)!
        return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        var cal = calendar
        cal.locale = Localizer.shared.language.locale
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}
