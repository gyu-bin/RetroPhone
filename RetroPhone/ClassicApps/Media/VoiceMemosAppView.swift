import AVFoundation
import Combine
import SwiftUI
import UIKit

struct VoiceMemoRoute: Hashable { let id: UUID }
struct VoiceMemoLabelRoute: Hashable { let id: UUID }

// MARK: - Root

struct VoiceMemosAppView: View {
    @State private var recorder = VoiceRecorder()
    @State private var player = VoiceMemoPlayer()
    @State private var showList = false

    var body: some View {
        ZStack {
            recorderScreen
            if showList {
                VoiceMemoListScreen(player: player) {
                    withAnimation(.easeInOut(duration: 0.35)) { showList = false }
                }
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }
        }
        .preference(key: StatusBarStyleKey.self, value: showList ? nil : StatusBarStyle.black)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)) { note in
            recorder.handleInterruption(note)
        }
        .onDisappear {
            recorder.stop()
            player.stop()
        }
        .retroAlert(L("마이크 접근 권한이 필요합니다"), isPresented: $recorder.permissionDenied,
                    message: L("음성 메모를 녹음하려면 iOS 설정에서 마이크 접근을 허용하세요."),
                    buttons: [
                        RetroAlertButton(title: L("취소")),
                        RetroAlertButton(title: L("설정 열기"), isPreferred: true) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        },
                    ])
        .retroAlert(L("녹음할 수 없음"), isPresented: $recorder.failed,
                    message: L("녹음을 시작하거나 저장하는 중 오류가 발생했습니다."))
        .retroAlert(L("재생할 수 없음"), isPresented: $player.failed,
                    message: L("이 음성 메모를 재생할 수 없습니다."))
    }

    private var recorderScreen: some View {
        VStack(spacing: 0) {
            if recorder.state != .idle {
                RecordingBanner(elapsed: recorder.elapsed, paused: recorder.state == .paused)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ZStack {
                RadialGradient(colors: [Color(hex: 0x4E4E4E), Color(hex: 0x1E1E1E), Color.black],
                               center: .center, startRadius: 10, endRadius: 380)
                ChromeMicrophone()
                    .frame(maxWidth: 190)
                    .padding(.vertical, 28)
                    .shadow(color: .black.opacity(0.85), radius: 14, y: 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            controlPanel
        }
        .background(Color.black)
        .animation(.easeOut(duration: 0.2), value: recorder.state)
    }

    private var controlPanel: some View {
        HStack(spacing: 12) {
            RecordButton(state: recorder.state) {
                player.stop()
                Task { await recorder.recordOrPause() }
            }
            VUMeterView(level: recorder.needle)
            if recorder.state == .idle {
                PanelRoundButton(systemImage: "list.bullet", label: L("음성 메모 목록")) {
                    SoundService.shared.play(.tock)
                    withAnimation(.easeInOut(duration: 0.35)) { showList = true }
                }
            } else {
                PanelRoundButton(systemImage: "stop.fill", label: L("정지")) {
                    recorder.stop()
                }
            }
        }
        .padding(12)
        .background(
            ZStack {
                LinearGradient(colors: [Color(hex: 0x404040), Color(hex: 0x141414)], startPoint: .top, endPoint: .bottom)
                BrushedMetalTexture(lineAlpha: 0.07)
            }
        )
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.22)).frame(height: 1) }
    }
}

// MARK: - Recorder chrome

struct RecordingBanner: View {
    var elapsed: TimeInterval
    var paused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let on = paused || Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                Circle().fill(Color.white).frame(width: 8, height: 8).opacity(on ? 1 : 0.25)
            }
            Text(paused ? L("일시 정지됨") : L("녹음 중"))
                .font(.retroFixed(14, .bold))
            Spacer()
            Text(MediaFormat.duration(elapsed))
                .font(.retroFixed(14, .bold))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 0, y: -1)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(LinearGradient(colors: [Color(hex: 0xE8483C), Color(hex: 0xA3150C)], startPoint: .top, endPoint: .bottom))
        .accessibilityElement(children: .combine)
    }
}

/// Glossy round button: red record dot, or pause bars while recording.
/// Deliberately silent (no SoundService tock) so UI sounds never touch the recording session.
struct RecordButton: View {
    var state: VoiceRecorder.State
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0xE6E6E6), Color(hex: 0x7A7A7A)], startPoint: .top, endPoint: .bottom))
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0x2A2A2A), Color(hex: 0x4A4A4A)], startPoint: .top, endPoint: .bottom))
                    .padding(3)
                if state == .recording {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 1.5).frame(width: 6, height: 20)
                        RoundedRectangle(cornerRadius: 1.5).frame(width: 6, height: 20)
                    }
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFF6A5E), Color(hex: 0xC0140A)], startPoint: .top, endPoint: .bottom))
                } else {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: 0xFF6A5E), Color(hex: 0xC0140A)], startPoint: .top, endPoint: .bottom))
                        .overlay(
                            Ellipse()
                                .fill(LinearGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom))
                                .frame(width: 16, height: 9)
                                .offset(y: -6)
                        )
                        .frame(width: 26, height: 26)
                        .shadow(color: Color(hex: 0xFF3B30).opacity(0.6), radius: 4)
                }
            }
            .frame(width: 56, height: 56)
            .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(state == .recording ? L("일시 정지") : L("녹음"))
    }
}

struct PanelRoundButton: View {
    var systemImage: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0xE6E6E6), Color(hex: 0x7A7A7A)], startPoint: .top, endPoint: .bottom))
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0x2A2A2A), Color(hex: 0x4A4A4A)], startPoint: .top, endPoint: .bottom))
                    .padding(3)
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 0, y: -1)
            }
            .frame(width: 56, height: 56)
            .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(label)
    }
}

/// Analog VU meter: backlit cream dial, VU-law scale (-20…+3), red zone, black needle.
struct VUMeterView: View {
    var level: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x4E4E4E), Color(hex: 0x0E0E0E)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1))
            Canvas { ctx, size in
                Self.drawFace(&ctx, size: size, level: level)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                // glass glare
                LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.02)], startPoint: .top, endPoint: .center)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .allowsHitTesting(false)
            )
            .padding(5)
        }
        .aspectRatio(1.9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(L("입력 레벨"))
        .accessibilityValue("\(Int((level * 100).rounded()))%")
    }

    private static func drawFace(_ ctx: inout GraphicsContext, size: CGSize, level: Double) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF6CF), Color(hex: 0xF2D581), Color(hex: 0xC79E48)]),
                                       center: CGPoint(x: w / 2, y: h * 0.75), startRadius: 0, endRadius: w * 0.75))

        let pivot = CGPoint(x: w / 2, y: h * 1.12)
        let radius = h * 0.86
        let sweep = 48.0
        func point(_ fraction: Double, _ r: CGFloat) -> CGPoint {
            let a = (-sweep + 2 * sweep * fraction) * .pi / 180
            return CGPoint(x: pivot.x + r * CGFloat(sin(a)), y: pivot.y - r * CGFloat(cos(a)))
        }

        // Scale arc
        var arc = Path()
        for i in 0...60 {
            let p = point(Double(i) / 60, radius)
            if i == 0 { arc.move(to: p) } else { arc.addLine(to: p) }
        }
        ctx.stroke(arc, with: .color(Color(hex: 0x2A2A2A)), lineWidth: 1)

        // Red zone (0 … +3 VU)
        let zero = VUScale.fraction(forVU: 0)
        var red = Path()
        for i in 0...20 {
            let p = point(zero + (1 - zero) * Double(i) / 20, radius + 3)
            if i == 0 { red.move(to: p) } else { red.addLine(to: p) }
        }
        ctx.stroke(red, with: .color(Color(hex: 0xC81E14)), lineWidth: 5)

        // Ticks + labels
        for vu in VUScale.labels {
            let f = VUScale.fraction(forVU: vu)
            var tick = Path()
            tick.move(to: point(f, radius))
            tick.addLine(to: point(f, radius + 8))
            let hot = vu >= 0
            ctx.stroke(tick, with: .color(hot ? Color(hex: 0xB0160C) : Color(hex: 0x2A2A2A)), lineWidth: 1.2)
            let label = vu > 0 ? "+\(Int(vu))" : "\(Int(vu))"
            ctx.draw(Text(label)
                        .font(.retroFixed(8, .bold))
                        .foregroundStyle(hot ? Color(hex: 0xB0160C) : Color(hex: 0x2A2A2A)),
                     at: point(f, radius + 16))
        }
        ctx.draw(Text("VU").font(.retroFixed(15, .bold)).foregroundStyle(Color(hex: 0x2A2A2A)),
                 at: CGPoint(x: w / 2, y: h * 0.66))

        // Needle (with a soft shadow)
        let tip = point(max(0, min(1, level)), radius + 10)
        var needle = Path()
        needle.move(to: pivot)
        needle.addLine(to: tip)
        ctx.stroke(needle.offsetBy(dx: 2, dy: 2), with: .color(.black.opacity(0.18)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        ctx.stroke(needle, with: .color(Color(hex: 0x151515)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

        // Pivot cover
        let cover = CGRect(x: 0, y: h * 0.86, width: w, height: h * 0.14)
        ctx.fill(Path(cover), with: .linearGradient(Gradient(colors: [Color(hex: 0x3A3A3A), Color(hex: 0x0A0A0A)]),
                                                    startPoint: CGPoint(x: 0, y: cover.minY), endPoint: CGPoint(x: 0, y: cover.maxY)))
    }
}

/// Code-drawn chrome studio microphone (original artwork, evoking the iOS 4 Voice Memos screen).
struct ChromeMicrophone: View {
    var body: some View {
        Canvas { ctx, size in
            Self.draw(&ctx, size: size)
        }
        .aspectRatio(0.58, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private static let chrome = Gradient(stops: [
        .init(color: Color(hex: 0x6E6E6E), location: 0),
        .init(color: Color(hex: 0xF6F6F6), location: 0.22),
        .init(color: Color(hex: 0xC4C4C4), location: 0.42),
        .init(color: Color(hex: 0x5A5A5A), location: 0.68),
        .init(color: Color(hex: 0xD8D8D8), location: 0.88),
        .init(color: Color(hex: 0x7A7A7A), location: 1),
    ])

    private static func chromeFill(_ rect: CGRect) -> GraphicsContext.Shading {
        .linearGradient(chrome, startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY))
    }

    private static func rounded(_ rect: CGRect, _ radius: CGFloat) -> Path {
        Path(roundedRect: rect, cornerRadius: min(radius, rect.width / 2, rect.height / 2))
    }

    private static func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height

        // Stand
        let pole = CGRect(x: w * 0.44, y: h * 0.70, width: w * 0.12, height: h * 0.26)
        ctx.fill(Path(pole), with: chromeFill(pole))
        let base = CGRect(x: w * 0.32, y: h * 0.95, width: w * 0.36, height: h * 0.05)
        ctx.fill(rounded(base, h * 0.02), with: chromeFill(base))

        // Yoke
        let yokeRect = CGRect(x: w * 0.28, y: h * 0.60, width: w * 0.44, height: h * 0.12)
        var yoke = Path()
        yoke.move(to: CGPoint(x: yokeRect.minX, y: yokeRect.minY))
        yoke.addLine(to: CGPoint(x: yokeRect.maxX, y: yokeRect.minY))
        yoke.addLine(to: CGPoint(x: w * 0.58, y: yokeRect.maxY))
        yoke.addLine(to: CGPoint(x: w * 0.42, y: yokeRect.maxY))
        yoke.closeSubpath()
        ctx.fill(yoke, with: chromeFill(yokeRect))
        ctx.stroke(yoke, with: .color(.black.opacity(0.4)), lineWidth: 1)
        let knob = CGRect(x: w * 0.455, y: h * 0.635, width: w * 0.09, height: w * 0.09)
        ctx.fill(Path(ellipseIn: knob),
                 with: .radialGradient(Gradient(colors: [.white, Color(hex: 0x5A5A5A)]),
                                       center: CGPoint(x: knob.midX - knob.width * 0.2, y: knob.midY - knob.height * 0.2),
                                       startRadius: 0, endRadius: knob.width * 0.7))

        // Head
        let head = CGRect(x: w * 0.10, y: h * 0.005, width: w * 0.80, height: h * 0.63)
        let headPath = rounded(head, w * 0.38)
        ctx.fill(headPath, with: chromeFill(head))
        ctx.stroke(headPath, with: .color(.black.opacity(0.55)), lineWidth: 1)

        // Grille with horizontal slats and a centre rib
        let grille = head.insetBy(dx: w * 0.07, dy: w * 0.07)
        let grillePath = rounded(grille, w * 0.31)
        ctx.fill(grillePath, with: .color(Color(hex: 0x121212)))
        ctx.drawLayer { layer in
            layer.clip(to: grillePath)
            let step = max(4, h * 0.022)
            var y = grille.minY + step * 0.5
            while y < grille.maxY {
                let slat = CGRect(x: grille.minX, y: y, width: grille.width, height: step * 0.48)
                layer.fill(Path(slat), with: chromeFill(slat))
                y += step
            }
            let rib = CGRect(x: grille.midX - w * 0.05, y: grille.minY, width: w * 0.10, height: grille.height)
            layer.fill(Path(rib), with: chromeFill(rib))
            // Depth shading toward the edges of the grille
            layer.fill(Path(grille), with: .linearGradient(
                Gradient(colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(0.5)]),
                startPoint: CGPoint(x: grille.minX, y: grille.midY), endPoint: CGPoint(x: grille.maxX, y: grille.midY)))
        }
        ctx.stroke(grillePath, with: .color(.black.opacity(0.75)), lineWidth: 1.5)

        // Specular highlight
        let gloss = CGRect(x: head.minX + w * 0.1, y: head.minY + h * 0.03, width: w * 0.2, height: h * 0.3)
        ctx.fill(Path(ellipseIn: gloss),
                 with: .linearGradient(Gradient(colors: [.white.opacity(0.35), .white.opacity(0)]),
                                       startPoint: CGPoint(x: gloss.midX, y: gloss.minY),
                                       endPoint: CGPoint(x: gloss.midX, y: gloss.maxY)))
    }
}

// MARK: - Memo list

struct VoiceMemoListScreen: View {
    let player: VoiceMemoPlayer
    var onDone: () -> Void

    var body: some View {
        let store = VoiceMemoStore.shared
        NavigationStack {
            ClassicPage(title: L("음성 메모"), background: AnyView(Color.white),
                        leading: { EmptyView() },
                        trailing: {
                            ClassicBarButton(title: L("완료"), kind: .done) {
                                player.stop()
                                onDone()
                            }
                        }) {
                VStack(spacing: 0) {
                    if store.memos.isEmpty {
                        Text(L("음성 메모 없음"))
                            .font(.retro(20, .bold))
                            .foregroundStyle(Color(hex: 0x9A9A9A))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(store.memos) { memo in
                                    VoiceMemoRow(memo: memo, player: player)
                                }
                            }
                        }
                    }
                    if let id = player.playingID, let memo = store.memo(id: id) {
                        VoiceMemoPlaybackBar(memo: memo, player: player)
                    }
                }
            }
            .navigationDestination(for: VoiceMemoRoute.self) { route in
                VoiceMemoDetailPage(id: route.id, player: player)
            }
            .navigationDestination(for: VoiceMemoLabelRoute.self) { route in
                VoiceMemoLabelPage(id: route.id)
            }
        }
    }
}

struct VoiceMemoRow: View {
    let memo: VoiceMemo
    let player: VoiceMemoPlayer

    var body: some View {
        let active = player.playingID == memo.id
        let playing = active && player.isPlaying
        HStack(spacing: 10) {
            Button { player.toggle(memo) } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(LinearGradient(colors: active ? [Color(hex: 0x7AA3F2), Color(hex: 0x2D63DA)]
                                                                    : [Color(hex: 0xA0A0A0), Color(hex: 0x5E5E5E)],
                                                     startPoint: .top, endPoint: .bottom))
                    )
            }
            .buttonStyle(PressDimStyle())
            .accessibilityLabel(playing ? L("일시 정지") : L("재생"))

            VStack(alignment: .leading, spacing: 2) {
                Text(VoiceMemoStore.title(for: memo))
                    .font(.retro(17, .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                Text(RetroFormat.date(memo.createdAt, template: "yMMMd"))
                    .font(.retro(13))
                    .foregroundStyle(Color(hex: 0x7A7A7A))
            }
            Spacer(minLength: 8)
            Text(MediaFormat.duration(memo.duration))
                .font(.retro(15))
                .foregroundStyle(Color(hex: 0x385487))
            NavigationLink(value: VoiceMemoRoute(id: memo.id)) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(hex: 0x2F6BDB))
                    .frame(width: 34, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("세부사항"))
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background(active ? Color(hex: 0xE8F0FD) : Color.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xE0E0E0)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { player.toggle(memo) }
    }
}

struct VoiceMemoPlaybackBar: View {
    let memo: VoiceMemo
    let player: VoiceMemoPlayer
    @State private var scrub: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let total = player.duration > 0 ? player.duration : memo.duration
            let current = scrub ?? player.currentTime
            HStack(spacing: 8) {
                Text(MediaFormat.duration(current))
                    .frame(width: 40, alignment: .trailing)
                RetroScrubber(value: current, total: total,
                              onScrub: { scrub = $0 },
                              onCommit: { time in
                                  player.seek(to: time)
                                  scrub = nil
                              })
                Text("-" + MediaFormat.duration(max(0, total - current)))
                    .frame(width: 46, alignment: .leading)
            }
            .font(.retroFixed(12, .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(BarBackground(style: .black))
        }
    }
}

// MARK: - Detail

struct VoiceMemoDetailPage: View {
    let id: UUID
    let player: VoiceMemoPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        let store = VoiceMemoStore.shared
        ClassicPage(title: L("정보"), leading: { ClassicBackButton(title: L("음성 메모")) }, trailing: { EmptyView() }) {
            if let memo = store.memo(id: id) {
                ScrollView {
                    VStack(spacing: 0) {
                        GroupedSection {
                            NavigationLink(value: VoiceMemoLabelRoute(id: id)) {
                                TableRow(title: L("레이블"), detail: memo.label.map { L($0) } ?? L("레이블 없음"), chevron: true)
                            }
                            .buttonStyle(.plain)
                        }
                        GroupedSection {
                            TableRow(title: L("날짜"), detail: RetroFormat.date(memo.createdAt, template: "yMMMd"))
                            TableRow(title: L("녹음 시각"), detail: RetroFormat.time(memo.createdAt))
                            TableRow(title: L("길이"), detail: MediaFormat.duration(memo.duration))
                        }
                        VStack(spacing: 12) {
                            ShareLink(item: store.url(for: memo)) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text(L("공유"))
                                }
                                .font(.retro(19, .bold))
                                .foregroundStyle(Color(hex: 0x333333))
                                .shadow(color: .white, radius: 0, y: 1)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(LinearGradient(colors: [Color(hex: 0xF4F4F4), Color(hex: 0xC2C2C2)],
                                                           startPoint: .top, endPoint: .bottom))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.45), lineWidth: 1))
                            }
                            GlossyButton(title: L("음성 메모 삭제"), tint: .red) { confirmDelete = true }
                        }
                        .padding(20)
                    }
                }
            } else {
                Color.clear
            }
        }
        .retroAlert(L("이 음성 메모를 삭제하겠습니까?"), isPresented: $confirmDelete,
                    message: L("삭제한 음성 메모는 복구할 수 없습니다."),
                    buttons: [
                        RetroAlertButton(title: L("취소")),
                        RetroAlertButton(title: L("삭제"), isPreferred: true) {
                            if player.playingID == id { player.stop() }
                            store.delete(id: id)
                            dismiss()
                        },
                    ])
    }
}

struct VoiceMemoLabelPage: View {
    let id: UUID
    @State private var custom = ""

    var body: some View {
        let store = VoiceMemoStore.shared
        let current = store.memo(id: id)?.label
        ClassicPage(title: L("레이블"), leading: { ClassicBackButton(title: L("정보")) }, trailing: { EmptyView() }) {
            ScrollView {
                VStack(spacing: 0) {
                    GroupedSection {
                        labelRow(title: L("레이블 없음"), selected: current == nil) { store.setLabel(nil, for: id) }
                        ForEach(VoiceMemoStore.presetLabels, id: \.self) { key in
                            labelRow(title: L(key), selected: current == key) { store.setLabel(key, for: id) }
                        }
                    }
                    GroupedSection(header: L("사용자 설정")) {
                        TextField(L("레이블 입력"), text: $custom)
                            .font(.retro(17))
                            .submitLabel(.done)
                            .onSubmit {
                                let text = custom.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !text.isEmpty { store.setLabel(text, for: id) }
                            }
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            if let current, !VoiceMemoStore.presetLabels.contains(current) { custom = current }
        }
    }

    private func labelRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            TableRow(title: title) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: 0x385487))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
