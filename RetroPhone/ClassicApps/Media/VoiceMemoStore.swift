import AVFoundation
import Foundation
import Observation

// MARK: - Store

struct VoiceMemo: Codable, Identifiable, Hashable {
    var id: UUID
    var fileName: String
    var createdAt: Date
    var duration: TimeInterval
    /// Korean preset key (e.g. "인터뷰") or user-entered text. nil = no label.
    var label: String?
}

/// Recordings live as AAC .m4a files in Application Support/RetroPhone/VoiceMemos with a small
/// JSON index (labels, durations). Files without an index entry are picked up on load.
@Observable
final class VoiceMemoStore {
    static let shared = VoiceMemoStore()
    private static let indexName = "VoiceMemos/index.json"

    private(set) var memos: [VoiceMemo] = []

    static var directory: URL {
        let dir = FileStore.baseURL.appendingPathComponent("VoiceMemos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() { load() }

    func load() {
        let dir = Self.directory
        let saved = FileStore.load([VoiceMemo].self, from: Self.indexName) ?? []
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let audio = files.filter { $0.pathExtension.lowercased() == "m4a" }
        let names = Set(audio.map(\.lastPathComponent))
        var result = saved.filter { names.contains($0.fileName) }
        let known = Set(result.map(\.fileName))
        for url in audio where !known.contains(url.lastPathComponent) {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            let duration = (try? AVAudioPlayer(contentsOf: url).duration) ?? 0
            result.append(VoiceMemo(id: UUID(), fileName: url.lastPathComponent, createdAt: created, duration: duration, label: nil))
        }
        memos = result.sorted { $0.createdAt > $1.createdAt }
        if result.count != saved.count { save() }
    }

    func url(for memo: VoiceMemo) -> URL {
        Self.directory.appendingPathComponent(memo.fileName)
    }

    func memo(id: UUID) -> VoiceMemo? { memos.first { $0.id == id } }

    func add(_ memo: VoiceMemo) {
        memos.insert(memo, at: 0)
        save()
    }

    func setLabel(_ label: String?, for id: UUID) {
        guard let index = memos.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        memos[index].label = (trimmed?.isEmpty ?? true) ? nil : trimmed
        save()
    }

    func delete(id: UUID) {
        guard let index = memos.firstIndex(where: { $0.id == id }) else { return }
        let memo = memos.remove(at: index)
        try? FileManager.default.removeItem(at: url(for: memo))
        save()
    }

    private func save() {
        _ = Self.directory
        FileStore.save(memos, to: Self.indexName)
    }

    /// Preset labels from the iOS 4 Voice Memos app (Korean keys, localized at display time).
    static let presetLabels = ["팟캐스트", "인터뷰", "강의", "아이디어", "회의", "메모"]

    static func title(for memo: VoiceMemo) -> String {
        if let label = memo.label { return L(label) }
        return RetroFormat.time(memo.createdAt)
    }
}

// MARK: - VU scale (pure)

/// Classic VU meter ballistics mapping. 0 VU is referenced to -18 dBFS; the dial runs from
/// -20 VU to +3 VU and is linear in signal *voltage*, like a real VU scale.
nonisolated enum VUScale {
    static let referenceDBFS = -18.0
    static let minVU = -20.0
    static let maxVU = 3.0
    static let labels: [Double] = [-20, -10, -7, -5, -3, -1, 0, 1, 2, 3]

    static func fraction(forVU vu: Double) -> Double {
        let a = pow(10, vu / 20), lo = pow(10, minVU / 20), hi = pow(10, maxVU / 20)
        return min(1, max(0, (a - lo) / (hi - lo)))
    }

    static func fraction(forDBFS db: Double) -> Double {
        guard db.isFinite else { return 0 }
        return fraction(forVU: db - referenceDBFS)
    }
}

// MARK: - Audio session

enum VoiceMemoAudioSession {
    /// Back to the app-wide UI-sound category (same as SoundService) and let other audio resume.
    static func restore() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.ambient, options: [.mixWithOthers])
    }
}

// MARK: - Recorder

@Observable
final class VoiceRecorder {
    enum State { case idle, recording, paused }

    private(set) var state: State = .idle
    /// Smoothed VU needle position, 0…1.
    private(set) var needle: Double = 0
    private(set) var elapsed: TimeInterval = 0
    var permissionDenied = false
    var failed = false

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var starting = false
    @ObservationIgnored private let relay = RecorderDelegateRelay()

    init() {
        relay.onFailure = { @Sendable [weak self] in
            Task { @MainActor in self?.recordingFailed() }
        }
    }

    static var hasDeniedPermission: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    func recordOrPause() async {
        switch state {
        case .idle: await start()
        case .recording: pause()
        case .paused: resume()
        }
    }

    func start() async {
        guard state == .idle, !starting else { return }
        starting = true
        defer { starting = false }

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .undetermined:
            guard await AVAudioApplication.requestRecordPermission() else {
                permissionDenied = true
                return
            }
        case .denied:
            permissionDenied = true
            return
        @unknown default:
            permissionDenied = true
            return
        }

        SoundService.shared.play(.recordStart)
        try? await Task.sleep(for: .milliseconds(320))

        let session = AVAudioSession.sharedInstance()
        let url = VoiceMemoStore.directory.appendingPathComponent(Self.fileName(for: Date()))
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = relay
            recorder.isMeteringEnabled = true
            guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
            fileURL = url
            startedAt = Date()
            elapsed = 0
            state = .recording
            startTimer()
            Haptics.tap(.medium)
        } catch {
            try? FileManager.default.removeItem(at: url)
            VoiceMemoAudioSession.restore()
            failed = true
        }
    }

    func pause() {
        guard state == .recording, let recorder else { return }
        recorder.pause()
        state = .paused
        Haptics.tap()
    }

    func resume() {
        guard state == .paused, let recorder else { return }
        if recorder.record() { state = .recording }
        Haptics.tap()
    }

    /// Stops and saves the recording (anything shorter than ~0.3 s is discarded).
    func stop() {
        guard let recorder, let url = fileURL else { return }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        fileURL = nil
        stopTimer()
        state = .idle
        needle = 0
        elapsed = 0
        VoiceMemoAudioSession.restore()
        SoundService.shared.play(.recordStop)
        if duration >= 0.3 {
            VoiceMemoStore.shared.add(VoiceMemo(id: UUID(), fileName: url.lastPathComponent, createdAt: startedAt,
                                                duration: duration, label: nil))
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Called for AVAudioSession interruption notifications (phone call, Siri…).
    func handleInterruption(_ note: Notification) {
        let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
        if state == .recording { pause() }
    }

    private func recordingFailed() {
        guard recorder != nil else { return }
        stop()
        failed = true
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let recorder, state == .recording else {
            needle += (0 - needle) * 0.2
            return
        }
        recorder.updateMeters()
        let target = VUScale.fraction(forDBFS: Double(recorder.averagePower(forChannel: 0)))
        // Needle ballistics: quicker rise than fall.
        let k = target > needle ? 0.45 : 0.16
        needle += (target - needle) * k
        elapsed = recorder.currentTime
    }

    private static func fileName(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "Memo-\(f.string(from: date)).m4a"
    }
}

/// AVAudioRecorderDelegate callbacks may arrive off the main thread.
nonisolated final class RecorderDelegateRelay: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    /// Set once on the main actor before recording starts.
    var onFailure: (@Sendable () -> Void)?

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag { onFailure?() }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        onFailure?()
    }
}

// MARK: - Player

@Observable
final class VoiceMemoPlayer {
    private(set) var playingID: UUID?
    private(set) var isPlaying = false
    var failed = false

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private let relay = PlayerDelegateRelay()

    init() {
        relay.onFinish = { @Sendable [weak self] in
            Task { @MainActor in self?.finished() }
        }
    }

    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var duration: TimeInterval { player?.duration ?? 0 }

    func toggle(_ memo: VoiceMemo) {
        if playingID == memo.id, let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
            } else {
                activate()
                isPlaying = player.play()
            }
            return
        }
        stop()
        do {
            activate()
            let player = try AVAudioPlayer(contentsOf: VoiceMemoStore.shared.url(for: memo))
            player.delegate = relay
            player.prepareToPlay()
            guard player.play() else { throw CocoaError(.fileReadUnknown) }
            self.player = player
            playingID = memo.id
            isPlaying = true
        } catch {
            VoiceMemoAudioSession.restore()
            failed = true
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
    }

    func stop() {
        guard player != nil || playingID != nil else { return }
        player?.stop()
        player = nil
        playingID = nil
        isPlaying = false
        VoiceMemoAudioSession.restore()
    }

    private func finished() {
        player = nil
        playingID = nil
        isPlaying = false
        VoiceMemoAudioSession.restore()
    }

    private func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }
}

/// AVAudioPlayerDelegate callbacks may arrive off the main thread.
nonisolated final class PlayerDelegateRelay: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    /// Set once on the main actor before playback starts.
    var onFinish: (@Sendable () -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onFinish?()
    }
}
