import AVFoundation
import UIKit

/// All UI sounds are synthesized at runtime (original work — no Apple audio assets are used).
/// Uses the `.ambient` session category so the ringer/silent switch is respected and other audio
/// (e.g. Music) keeps playing.
final class SoundService {
    static let shared = SoundService()

    enum Effect: CaseIterable, Hashable {
        case unlock, lock, keyClick, shutter, tock, folderOpen, folderClose
        case recordStart, recordStop, alarm, timerDone
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var dtmfBuffers: [Character: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var started = false

    private var settings: RetroSettings { SettingsStore.shared.value }

    private init() {}

    private func startIfNeeded() -> Bool {
        if started && engine.isRunning { return true }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            if players.isEmpty {
                for _ in 0..<5 {
                    let p = AVAudioPlayerNode()
                    engine.attach(p)
                    engine.connect(p, to: engine.mainMixerNode, format: format)
                    players.append(p)
                }
            }
            try engine.start()
            players.forEach { $0.play() }
            started = true
            return true
        } catch {
            return false
        }
    }

    func play(_ effect: Effect) {
        guard settings.soundEnabled else { return }
        if effect == .keyClick && !settings.keyboardClicks { return }
        guard startIfNeeded() else { return }
        let buffer = buffers[effect] ?? {
            let b = makeBuffer(Self.synthesize(effect))
            buffers[effect] = b
            return b
        }()
        schedule(buffer)
    }

    /// Standard DTMF dual-tone for the phone keypad (0-9, *, #).
    func playDTMF(_ key: Character) {
        guard settings.soundEnabled, startIfNeeded() else { return }
        let buffer = dtmfBuffers[key] ?? {
            let b = makeBuffer(Self.dtmf(key))
            dtmfBuffers[key] = b
            return b
        }()
        schedule(buffer)
    }

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        let player = players[nextPlayer % players.count]
        nextPlayer += 1
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        if !player.isPlaying { player.play() }
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let ch = buffer.floatChannelData![0]
        for (i, s) in samples.enumerated() { ch[i] = s }
        return buffer
    }

    // MARK: Synthesis

    static let rate: Float = 44_100

    /// Exposed for unit tests.
    static func synthesize(_ effect: Effect) -> [Float] {
        switch effect {
        case .unlock:
            // Two-stage mechanical latch: bright click then a softer, lower clack.
            return mix(click(freq: 2600, ms: 18, gain: 0.55, noise: 0.5),
                       offsetMs: 55, click(freq: 1400, ms: 34, gain: 0.45, noise: 0.35))
        case .lock:
            return mix(click(freq: 900, ms: 40, gain: 0.6, noise: 0.45),
                       offsetMs: 20, click(freq: 480, ms: 60, gain: 0.35, noise: 0.2))
        case .keyClick:
            return click(freq: 3200, ms: 9, gain: 0.35, noise: 0.7)
        case .tock:
            return click(freq: 1500, ms: 16, gain: 0.3, noise: 0.25)
        case .folderOpen:
            return sweep(from: 500, to: 900, ms: 70, gain: 0.18)
        case .folderClose:
            return sweep(from: 900, to: 500, ms: 70, gain: 0.18)
        case .shutter:
            // Leaf shutter: open snap, short mechanical rattle, close snap.
            let open = click(freq: 2200, ms: 25, gain: 0.6, noise: 0.85)
            let close = click(freq: 1700, ms: 45, gain: 0.55, noise: 0.85)
            return mix(open, offsetMs: 90, close)
        case .recordStart:
            return mix(tone(880, ms: 90, gain: 0.3), offsetMs: 110, tone(1320, ms: 120, gain: 0.3))
        case .recordStop:
            return mix(tone(1320, ms: 90, gain: 0.3), offsetMs: 110, tone(880, ms: 120, gain: 0.3))
        case .alarm:
            var out: [Float] = []
            for _ in 0..<4 { out += tone(1046, ms: 120, gain: 0.45) + silence(ms: 80) }
            return out + silence(ms: 400)
        case .timerDone:
            var out: [Float] = []
            for f in [784.0, 988.0, 1175.0] as [Float] { out += tone(f, ms: 140, gain: 0.4) + silence(ms: 40) }
            return out
        }
    }

    static func dtmf(_ key: Character) -> [Float] {
        let rows: [Character: Float] = ["1": 697, "2": 697, "3": 697, "4": 770, "5": 770, "6": 770,
                                        "7": 852, "8": 852, "9": 852, "*": 941, "0": 941, "#": 941]
        let cols: [Character: Float] = ["1": 1209, "4": 1209, "7": 1209, "*": 1209,
                                        "2": 1336, "5": 1336, "8": 1336, "0": 1336,
                                        "3": 1477, "6": 1477, "9": 1477, "#": 1477]
        guard let r = rows[key], let c = cols[key] else { return [] }
        let n = Int(rate * 0.16)
        return (0..<n).map { i in
            let t = Float(i) / rate
            let env = min(1, Float(i) / 200) * min(1, Float(n - i) / 400)
            return 0.22 * env * (sin(2 * .pi * r * t) + sin(2 * .pi * c * t))
        }
    }

    private static func click(freq: Float, ms: Float, gain: Float, noise: Float) -> [Float] {
        let n = Int(rate * ms / 1000)
        var seed: UInt32 = 0x9E3779B9
        return (0..<n).map { i in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let white = Float(seed >> 8) / Float(1 << 24) * 2 - 1
            let t = Float(i) / rate
            let env = exp(-t * 1000 / (ms * 0.28))
            let attack = min(1, Float(i) / 12)
            return gain * attack * env * ((1 - noise) * sin(2 * .pi * freq * t) + noise * white)
        }
    }

    private static func tone(_ freq: Float, ms: Float, gain: Float) -> [Float] {
        let n = Int(rate * ms / 1000)
        return (0..<n).map { i in
            let t = Float(i) / rate
            let env = min(1, Float(i) / 220) * min(1, Float(n - i) / 660)
            return gain * env * sin(2 * .pi * freq * t)
        }
    }

    private static func sweep(from f0: Float, to f1: Float, ms: Float, gain: Float) -> [Float] {
        let n = Int(rate * ms / 1000)
        var phase: Float = 0
        return (0..<n).map { i in
            let p = Float(i) / Float(n)
            phase += 2 * .pi * (f0 + (f1 - f0) * p) / rate
            let env = sin(.pi * p)
            return gain * env * sin(phase)
        }
    }

    private static func silence(ms: Float) -> [Float] { Array(repeating: 0, count: Int(rate * ms / 1000)) }

    private static func mix(_ a: [Float], offsetMs: Float, _ b: [Float]) -> [Float] {
        let offset = Int(rate * offsetMs / 1000)
        var out = a + Array(repeating: 0, count: max(0, offset + b.count - a.count))
        for (i, s) in b.enumerated() { out[offset + i] = max(-1, min(1, out[offset + i] + s)) }
        return out
    }
}

/// Haptic feedback, gated by the user's setting.
enum Haptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard SettingsStore.shared.value.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() {
        guard SettingsStore.shared.value.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        guard SettingsStore.shared.value.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func selection() {
        guard SettingsStore.shared.value.hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
