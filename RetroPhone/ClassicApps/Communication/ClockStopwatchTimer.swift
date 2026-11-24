import SwiftUI
import Observation
import UIKit
import UserNotifications

// MARK: - Stopwatch model (Date-based, survives leaving the app)

nonisolated struct StopwatchState: Codable, Sendable {
    var accumulated: TimeInterval = 0
    var startedAt: Date?
    /// Total elapsed time at each lap press.
    var lapMarks: [TimeInterval] = []
}

@Observable
final class ClockStopwatch {
    static let shared = ClockStopwatch()
    private static let file = "clock_stopwatch.json"

    private(set) var state: StopwatchState

    private init() {
        state = FileStore.load(StopwatchState.self, from: Self.file) ?? StopwatchState()
    }

    var isRunning: Bool { state.startedAt != nil }

    func elapsed(at now: Date) -> TimeInterval {
        state.accumulated + (state.startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    func start() {
        guard !isRunning else { return }
        state.startedAt = Date()
        save()
    }

    func stop() {
        guard let started = state.startedAt else { return }
        state.accumulated += max(0, Date().timeIntervalSince(started))
        state.startedAt = nil
        save()
    }

    func lap() {
        guard isRunning else { return }
        state.lapMarks.append(elapsed(at: Date()))
        save()
    }

    func reset() {
        state = StopwatchState()
        save()
    }

    private func save() { FileStore.save(state, to: Self.file) }

    static func format(_ t: TimeInterval) -> String {
        let tenths = Int((max(0, t) * 10).rounded(.down))
        let h = tenths / 36_000
        let m = (tenths / 600) % 60
        let s = (tenths / 10) % 60
        let d = tenths % 10
        return h > 0 ? String(format: "%d:%02d:%02d.%d", h, m, s, d) : String(format: "%02d:%02d.%d", m, s, d)
    }
}

// MARK: - Stopwatch view

struct ClockStopwatchView: View {
    private var model: ClockStopwatch { ClockStopwatch.shared }

    var body: some View {
        NavigationStack {
            ClassicPage(title: L("스톱워치"), leading: { EmptyView() }, trailing: { EmptyView() }) {
                VStack(spacing: 0) {
                    TimelineView(.animation(minimumInterval: 0.05, paused: !model.isRunning)) { context in
                        let total = model.elapsed(at: context.date)
                        let lapStart = model.state.lapMarks.last ?? 0
                        ClockLCDPanel(primary: ClockStopwatch.format(total),
                                      secondary: model.state.lapMarks.isEmpty ? nil : ClockStopwatch.format(total - lapStart))
                    }
                    buttons
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    lapList
                }
            }
        }
    }

    private var buttons: some View {
        let running = model.isRunning
        let hasTime = model.elapsed(at: Date()) > 0
        return HStack(spacing: 12) {
            GlossyButton(title: running ? L("랩") : L("재설정"), tint: .gray) {
                if running { model.lap() } else { model.reset() }
            }
            .disabled(!running && !hasTime)
            .opacity(!running && !hasTime ? 0.6 : 1)
            GlossyButton(title: running ? L("정지") : L("시작"), tint: running ? .red : .green) {
                if running { model.stop() } else { model.start() }
            }
        }
    }

    private var lapList: some View {
        let marks = model.state.lapMarks
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(marks.indices.reversed()), id: \.self) { i in
                    let duration = marks[i] - (i > 0 ? marks[i - 1] : 0)
                    PlainRow {
                        HStack {
                            Text(LF("랩 %d", i + 1))
                                .font(.retro(17, .bold))
                                .foregroundStyle(.black)
                            Spacer()
                            Text(ClockStopwatch.format(duration))
                                .font(.retroFixed(17, .bold))
                                .monospacedDigit()
                                .foregroundStyle(Color(hex: 0x385487))
                        }
                    }
                }
            }
        }
        .background(marks.isEmpty ? Color.clear : Color.white)
    }
}

/// Light "LCD" panel used by the stopwatch and timer.
struct ClockLCDPanel: View {
    var primary: String
    var secondary: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(primary)
                .font(.retroFixed(54, .bold))
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0x111111))
                .shadow(color: .white, radius: 0, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let secondary {
                Text(secondary)
                    .font(.retroFixed(20, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x5A5F69))
                    .shadow(color: .white, radius: 0, y: 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 24)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xD3D7DD)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color(hex: 0x8E939C)).frame(height: 1)
            }
        )
    }
}

// MARK: - Countdown timer model

nonisolated struct CountdownState: Codable, Sendable {
    var running = false
    var paused = false
    var endDate: Date?
    var pausedRemaining: TimeInterval = 0
    var lastDuration: TimeInterval = 300
}

@Observable
final class ClockCountdown {
    static let shared = ClockCountdown()
    private static let file = "clock_timer.json"

    enum Phase { case idle, running, paused }

    private(set) var state: CountdownState
    var finishedAlert = false
    @ObservationIgnored private var ticker: Timer?

    private init() {
        var restored = FileStore.load(CountdownState.self, from: Self.file) ?? CountdownState()
        if restored.running, let end = restored.endDate, end <= Date() {
            restored.running = false
            restored.endDate = nil
        }
        state = restored
        if state.running { armTicker() }
    }

    var phase: Phase {
        if state.running { return .running }
        if state.paused { return .paused }
        return .idle
    }

    func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .running: return max(0, (state.endDate ?? now).timeIntervalSince(now))
        case .paused: return state.pausedRemaining
        case .idle: return 0
        }
    }

    func start(seconds: TimeInterval) {
        guard seconds >= 1 else { return }
        state.lastDuration = seconds
        state.running = true
        state.paused = false
        state.endDate = Date().addingTimeInterval(seconds)
        save()
        armTicker()
        scheduleNotification()
    }

    func pause() {
        guard phase == .running else { return }
        state.pausedRemaining = remaining(at: Date())
        state.running = false
        state.paused = true
        state.endDate = nil
        ticker?.invalidate()
        cancelNotification()
        save()
    }

    func resume() {
        guard phase == .paused else { return }
        state.running = true
        state.paused = false
        state.endDate = Date().addingTimeInterval(state.pausedRemaining)
        save()
        armTicker()
        scheduleNotification()
    }

    func cancel() {
        state.running = false
        state.paused = false
        state.endDate = nil
        ticker?.invalidate()
        cancelNotification()
        save()
    }

    /// Called by the notification delegate when the timer notification arrives in the foreground.
    func handleDeliveredNotification() {
        if phase == .running, let end = state.endDate, end <= Date().addingTimeInterval(1) { finish() }
    }

    private func armTicker() {
        ticker?.invalidate()
        guard let end = state.endDate else { return }
        let t = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func finish() {
        guard phase == .running else { return }
        let overdue = Date().timeIntervalSince(state.endDate ?? Date())
        state.running = false
        state.endDate = nil
        ticker?.invalidate()
        save()
        // Only sound in-app when we're actually on screen at the right moment; otherwise iOS
        // already delivered the notification.
        if UIApplication.shared.applicationState == .active && overdue < 3 {
            cancelNotification()
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [ClockNotificationIDs.timer])
            SoundService.shared.play(.timerDone)
            Haptics.success()
        }
        finishedAlert = true
    }

    private func scheduleNotification() {
        Task {
            guard await ClockNotifications.ensureAuthorized() else { return }
            guard phase == .running, let end = state.endDate else { return }
            let content = UNMutableNotificationContent()
            content.title = L("타이머")
            content.body = L("타이머가 종료되었습니다.")
            content.sound = UNNotificationSound.default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
            let request = UNNotificationRequest(identifier: ClockNotificationIDs.timer, content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [ClockNotificationIDs.timer])
    }

    private func save() { FileStore.save(state, to: Self.file) }

    static func format(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.up))
        return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}

// MARK: - Timer view

struct ClockTimerView: View {
    @State private var hours = 0
    @State private var minutes = 5
    @State private var seconds = 0
    @State private var loaded = false

    private var model: ClockCountdown { ClockCountdown.shared }

    private var pickedSeconds: TimeInterval { TimeInterval(hours * 3600 + minutes * 60 + seconds) }

    var body: some View {
        NavigationStack {
            ClassicPage(title: L("타이머"), leading: { EmptyView() }, trailing: { EmptyView() }) {
                VStack(spacing: 0) {
                    if model.phase == .idle {
                        pickers
                    } else {
                        TimelineView(.periodic(from: .now, by: 0.25)) { context in
                            ClockLCDPanel(primary: ClockCountdown.format(model.remaining(at: context.date)),
                                          secondary: model.phase == .paused ? L("일시 정지됨") : nil)
                        }
                    }
                    GroupedSection {
                        TableRow(title: L("타이머 종료 시"), detail: L("알림음"))
                    }
                    CommNote(text: L("RetroPhone이 백그라운드에 있거나 화면이 꺼져 있으면 iOS 알림으로 종료를 알려줍니다."))
                    Spacer(minLength: 0)
                    controls
                        .padding(.horizontal, 12)
                        .padding(.bottom, 14)
                }
            }
        }
        .retroAlert(L("타이머 완료"), isPresented: Binding(get: { model.finishedAlert },
                                                       set: { model.finishedAlert = $0 }))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let last = Int(model.state.lastDuration)
            hours = last / 3600
            minutes = (last / 60) % 60
            seconds = last % 60
        }
    }

    private var pickers: some View {
        HStack(spacing: 0) {
            wheel($hours, range: 0..<24, unit: L("시간"))
            wheel($minutes, range: 0..<60, unit: L("분"))
            wheel($seconds, range: 0..<60, unit: L("초"))
        }
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
        .environment(\.colorScheme, .light)
        .padding(10)
        .background(
            LinearGradient(colors: [Color(hex: 0x2B2B2F), Color(hex: 0x4A4C55)], startPoint: .top, endPoint: .bottom)
        )
    }

    private func wheel(_ value: Binding<Int>, range: Range<Int>, unit: String) -> some View {
        HStack(spacing: 0) {
            Picker(unit, selection: value) {
                ForEach(range, id: \.self) { n in
                    Text(verbatim: "\(n)").font(.retroFixed(22, .bold)).tag(n)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .clipped()
            Text(unit)
                .font(.retro(14, .bold))
                .foregroundStyle(Color(hex: 0x333333))
                .fixedSize()
        }
    }

    @ViewBuilder private var controls: some View {
        switch model.phase {
        case .idle:
            GlossyButton(title: L("시작"), tint: .green) {
                model.start(seconds: pickedSeconds)
            }
            .disabled(pickedSeconds < 1)
            .opacity(pickedSeconds < 1 ? 0.6 : 1)
        case .running, .paused:
            HStack(spacing: 12) {
                GlossyButton(title: L("취소"), tint: .gray) { model.cancel() }
                if model.phase == .running {
                    GlossyButton(title: L("일시 정지"), tint: .red) { model.pause() }
                } else {
                    GlossyButton(title: L("재개"), tint: .green) { model.resume() }
                }
            }
        }
    }
}
