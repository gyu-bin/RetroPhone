import AVFoundation
import Photos
import SwiftUI
import UIKit

// MARK: - Options

enum CameraFlashMode: String, CaseIterable, Identifiable {
    case auto, on, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: L("자동")
        case .on: L("켬")
        case .off: L("끔")
        }
    }
    var avMode: AVCaptureDevice.FlashMode {
        switch self {
        case .auto: .auto
        case .on: .on
        case .off: .off
        }
    }
}

enum CameraLook: String, CaseIterable, Identifiable {
    case original, iPhone4, iPhone4S, iPhone5
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: L("원본")
        case .iPhone4: "iPhone 4"
        case .iPhone4S: "iPhone 4S"
        case .iPhone5: "iPhone 5"
        }
    }
    var preset: RetroFilterPreset? {
        switch self {
        case .original: nil
        case .iPhone4: .iPhone4
        case .iPhone4S: .iPhone4S
        case .iPhone5: .iPhone5
        }
    }
}

// MARK: - Model

@Observable
final class CameraModel {
    enum Phase { case idle, unavailable, requesting, denied, configuring, running, failed }

    private(set) var phase: Phase = .idle
    private(set) var position: AVCaptureDevice.Position = .back
    private(set) var hasFlash = false
    private(set) var canSwitch = false
    private(set) var isBusy = false
    private(set) var lastThumbnail: UIImage?
    /// 0 = iris closed, 1 = fully open.
    var irisOpenness: CGFloat = 0
    var saveFailed = false
    var focusPoint: CGPoint?

    @ObservationIgnored let engine = CaptureEngine()
    @ObservationIgnored weak var previewLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    /// Strong reference: the rotation coordinator only holds the device weakly.
    @ObservationIgnored private var currentDevice: AVCaptureDevice?
    @ObservationIgnored private var captureStartedAt = Date.distantPast
    @ObservationIgnored private var configureToken = 0

    static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    func start() async {
        let back = Self.device(for: .back)
        let front = Self.device(for: .front)
        guard back != nil || front != nil else {
            phase = .unavailable
            return
        }
        canSwitch = back != nil && front != nil
        if back == nil { position = .front }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            phase = .requesting
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { phase = .denied; return }
        case .denied, .restricted:
            phase = .denied
            return
        @unknown default:
            phase = .denied
            return
        }
        await loadLastLibraryThumbnail()
        configure()
    }

    func stop() {
        engine.stop()
        irisOpenness = 0
        if phase == .running || phase == .configuring { phase = .idle }
    }

    private func configure() {
        guard let device = Self.device(for: position) else {
            phase = .failed
            return
        }
        if phase != .running { phase = .configuring }
        hasFlash = device.hasFlash
        configureToken += 1
        let token = configureToken
        let id = device.uniqueID
        engine.configure(deviceID: id) { [weak self] ok in
            Task { @MainActor in self?.didConfigure(ok, deviceID: id, token: token) }
        }
    }

    private func didConfigure(_ ok: Bool, deviceID: String, token: Int) {
        guard token == configureToken else { return }
        guard ok, let device = AVCaptureDevice(uniqueID: deviceID) else {
            phase = .failed
            return
        }
        currentDevice = device
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        if let connection = previewLayer?.connection {
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        }
        engine.start()
        phase = .running
        withAnimation(.easeOut(duration: 0.45).delay(0.35)) { irisOpenness = 1 }
    }

    func switchCamera() {
        guard canSwitch, phase == .running, !isBusy else { return }
        Haptics.tap()
        withAnimation(.easeIn(duration: 0.18)) { irisOpenness = 0 }
        position = position == .back ? .front : .back
        configure()
    }

    func focus(atLayerPoint point: CGPoint) {
        guard phase == .running, let layer = previewLayer else { return }
        let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: point)
        engine.focus(at: devicePoint)
        focusPoint = point
        let marker = point
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            if self?.focusPoint == marker { withAnimation(.easeOut(duration: 0.25)) { self?.focusPoint = nil } }
        }
    }

    func capture(look: CameraLook, flash: CameraFlashMode) {
        guard phase == .running, !isBusy else { return }
        isBusy = true
        captureStartedAt = Date()
        Haptics.tap(.medium)
        SoundService.shared.play(.shutter)
        withAnimation(.easeIn(duration: 0.12)) { irisOpenness = 0 }

        let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
        let preset = look.preset
        engine.capture(flash: hasFlash ? flash.avMode : .off,
                       rotationAngle: angle,
                       preferHEVC: preset == nil,
                       willCapture: {},
                       completion: { [weak self] data in
            let owner = self
            guard let data else {
                Task { @MainActor in owner?.captureFinished(nil, thumbnail: nil) }
                return
            }
            // Filtering is CPU/GPU heavy: keep it off both the main thread and the
            // AVFoundation delegate queue.
            DispatchQueue.global(qos: .userInitiated).async {
                let output = preset.flatMap { RetroPhotoProcessor.process(data, preset: $0) } ?? data
                let thumb = RetroPhotoProcessor.thumbnail(output, maxPixel: 180).map { UIImage(cgImage: $0) }
                Task { @MainActor in owner?.captureFinished(output, thumbnail: thumb) }
            }
        })

        // Safety net: never leave the shutter stuck closed.
        let started = captureStartedAt
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.isBusy, self.captureStartedAt == started else { return }
            self.captureFinished(nil, thumbnail: nil)
        }
    }

    private func captureFinished(_ data: Data?, thumbnail: UIImage?) {
        guard isBusy else { return }
        isBusy = false
        let elapsed = Date().timeIntervalSince(captureStartedAt)
        let delay = max(0, 0.25 - elapsed)
        Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            withAnimation(.easeOut(duration: 0.32)) { self?.irisOpenness = 1 }
        }
        guard let data else { return }
        if let thumbnail { withAnimation(.easeOut(duration: 0.3)) { lastThumbnail = thumbnail } }
        Task { @MainActor [weak self] in
            do {
                try await PhotoLibraryService.shared.save(data)
            } catch {
                self?.saveFailed = true
            }
        }
    }

    private func loadLastLibraryThumbnail() async {
        let library = PhotoLibraryService.shared
        guard library.canRead, let asset = library.recentAssets(limit: 1).firstObject else { return }
        lastThumbnail = await library.image(for: asset, size: CGSize(width: 180, height: 180))
    }
}

// MARK: - View

struct CameraAppView: View {
    @Environment(AppRouter.self) private var router
    @State private var model = CameraModel()
    @AppStorage("retro.camera.look") private var look: CameraLook = .original
    @AppStorage("retro.camera.flash") private var flash: CameraFlashMode = .auto
    @State private var flashExpanded = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.phase {
            case .unavailable:
                MediaPermissionView(systemImage: "camera", title: L("카메라를 사용할 수 없음"),
                                    message: L("이 기기에서는 카메라를 사용할 수 없습니다."))
            case .denied:
                MediaPermissionView(systemImage: "camera", title: L("카메라 접근 권한이 필요합니다"),
                                    message: L("사진을 촬영하려면 iOS 설정에서 카메라 접근을 허용하세요."), denied: true)
            case .failed:
                MediaPermissionView(systemImage: "exclamationmark.triangle", title: L("카메라를 시작할 수 없음"),
                                    message: L("다른 앱이 카메라를 사용 중일 수 있습니다."),
                                    requestTitle: L("다시 시도"), request: { Task { await model.start() } })
            default:
                cameraUI
            }
        }
        .retroStatusBarHidden()
        .task { await model.start() }
        .onDisappear { model.stop() }
        .retroAlert(L("사진을 저장할 수 없음"), isPresented: $model.saveFailed,
                    message: L("iOS 설정에서 사진 추가 권한을 확인하세요."))
    }

    private var cameraUI: some View {
        VStack(spacing: 0) {
            ZStack {
                CameraPreview(session: model.engine.session) { model.previewLayer = $0 }
                    .onTapGesture(coordinateSpace: .local) { location in
                        if flashExpanded {
                            withAnimation(.easeOut(duration: 0.2)) { flashExpanded = false }
                        } else {
                            model.focus(atLayerPoint: location)
                        }
                    }
                if let point = model.focusPoint {
                    FocusSquare()
                        .position(point)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 1.6).combined(with: .opacity))
                        .id("\(point.x)-\(point.y)")
                }
                IrisShutter(openness: model.irisOpenness)
                    .allowsHitTesting(false)
                VStack {
                    topControls
                    Spacer()
                    RetroSegmented(options: CameraLook.allCases.map { ($0, $0.title) }, selection: $look, style: .black)
                        .opacity(0.92)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 10)
                        .accessibilityLabel(L("필터"))
                }
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipped()
            Spacer(minLength: 0)
            bottomBar
        }
    }

    private var topControls: some View {
        HStack(alignment: .top) {
            if model.hasFlash {
                FlashModeControl(mode: $flash, expanded: $flashExpanded)
            }
            Spacer()
            if model.canSwitch && !flashExpanded {
                Button { model.switchCamera() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
                        .frame(width: 58, height: 34)
                        .background(CameraGlassBackground())
                }
                .buttonStyle(PressDimStyle())
                .accessibilityLabel(L("카메라 전환"))
            }
        }
        .padding(10)
    }

    private var bottomBar: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Color(hex: 0x6A6A6A), location: 0),
                .init(color: Color(hex: 0x3A3A3A), location: 0.08),
                .init(color: Color(hex: 0x262626), location: 0.6),
                .init(color: Color(hex: 0x141414), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            BrushedMetalTexture(lineAlpha: 0.08)
            VStack { Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1); Spacer() }
            HStack {
                Button {
                    SoundService.shared.play(.tock)
                    router.open(.photos)
                } label: {
                    ZStack {
                        Color(hex: 0x111111)
                        if let thumb = model.lastThumbnail {
                            Image(uiImage: thumb).resizable().scaledToFill()
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.85), lineWidth: 2))
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                }
                .buttonStyle(PressDimStyle())
                .accessibilityLabel(L("카메라 롤"))
                Spacer()
                ShutterButton(enabled: model.phase == .running && !model.isBusy) {
                    if flashExpanded { flashExpanded = false }
                    model.capture(look: look, flash: flash)
                }
                Spacer()
                Color.clear.frame(width: 48, height: 48)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 96)
    }
}

// MARK: - Controls

/// iOS 4 translucent grey glass used for the flash / switch-camera buttons.
struct CameraGlassBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
            .fill(LinearGradient(colors: [Color.white.opacity(0.42), Color.white.opacity(0.14)], startPoint: .top, endPoint: .bottom))
            .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.white.opacity(0.55), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
    }
}

/// Collapsed: ⚡ + current mode. Tapped: expands to 자동 / 켬 / 끔 like the iOS 4 camera.
struct FlashModeControl: View {
    @Binding var mode: CameraFlashMode
    @Binding var expanded: Bool

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 30)
            if expanded {
                ForEach(CameraFlashMode.allCases) { option in
                    Button {
                        Haptics.selection()
                        mode = option
                        withAnimation(.easeOut(duration: 0.2)) { expanded = false }
                    } label: {
                        Text(option.title)
                            .font(.retroFixed(14, .bold))
                            .foregroundStyle(option == mode ? Color(hex: 0xFFE14D) : .white)
                            .frame(minWidth: 44, minHeight: 34)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(mode.title)
                    .font(.retroFixed(14, .bold))
                    .padding(.trailing, 12)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
        .frame(height: 34)
        .padding(.leading, 4)
        .padding(.trailing, expanded ? 6 : 0)
        .background(CameraGlassBackground())
        .contentShape(Rectangle())
        .onTapGesture {
            guard !expanded else { return }
            SoundService.shared.play(.tock)
            withAnimation(.easeOut(duration: 0.2)) { expanded = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("플래시"))
        .accessibilityValue(mode.title)
    }
}

/// Big silver pill with a camera glyph.
struct ShutterButton: View {
    var enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xFDFDFD), Color(hex: 0xC9C9C9), Color(hex: 0x9C9C9C)],
                                         startPoint: .top, endPoint: .bottom))
                Capsule()
                    .stroke(LinearGradient(colors: [Color.white, Color(hex: 0x6A6A6A)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xE4E4E4), Color(hex: 0xB0B0B0)], startPoint: .top, endPoint: .bottom))
                    .padding(6)
                    .overlay(Capsule().stroke(Color.black.opacity(0.25), lineWidth: 1).padding(6))
                Image(systemName: "camera.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x3A3A3A))
                    .shadow(color: .white.opacity(0.8), radius: 0, y: 1)
            }
            .frame(width: 124, height: 58)
            .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
            .opacity(enabled ? 1 : 0.7)
        }
        .buttonStyle(PressDimStyle())
        .disabled(!enabled)
        .accessibilityLabel(L("사진 찍기"))
    }
}

/// iOS 4 blue tap-to-focus square.
struct FocusSquare: View {
    var body: some View {
        ZStack {
            Rectangle().stroke(Color(hex: 0x5AB4FF), lineWidth: 2)
            ForEach(0..<4) { i in
                Rectangle().fill(Color(hex: 0x5AB4FF)).frame(width: 2, height: 8)
                    .offset(y: -36)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
        }
        .frame(width: 80, height: 80)
        .shadow(color: .black.opacity(0.4), radius: 1)
    }
}

// MARK: - Iris shutter

nonisolated enum IrisGeometry {
    static let blades = 6

    static func vertices(in rect: CGRect, openness: CGFloat) -> [CGPoint] {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let halfDiagonal = hypot(rect.width, rect.height) / 2
        let maxRadius = halfDiagonal / cos(.pi / CGFloat(blades)) + 4
        let t = max(0, min(1, openness))
        let radius = maxRadius * t
        let twist = (1 - t) * .pi / 3
        return (0..<blades).map { i in
            let a = twist + CGFloat(i) * 2 * .pi / CGFloat(blades)
            return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        }
    }

    /// Direction of the polygon edge leaving vertex `i` (also the blade seam direction).
    static func edgeAngle(index i: Int, openness: CGFloat) -> CGFloat {
        let t = max(0, min(1, openness))
        let twist = (1 - t) * .pi / 3
        let a = twist + CGFloat(i) * 2 * .pi / CGFloat(blades)
        return a + .pi / 2 + .pi / CGFloat(blades)
    }
}

nonisolated struct IrisBladesShape: Shape {
    var openness: CGFloat
    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if openness > 0.001 {
            path.addLines(IrisGeometry.vertices(in: rect, openness: openness))
            path.closeSubpath()
        }
        return path
    }
}

nonisolated struct IrisSeamsShape: Shape {
    var openness: CGFloat
    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let vertices = IrisGeometry.vertices(in: rect, openness: openness)
        let length = hypot(rect.width, rect.height)
        for i in vertices.indices {
            let start = vertices[(i + 1) % vertices.count]
            let angle = IrisGeometry.edgeAngle(index: i, openness: openness)
            path.move(to: start)
            path.addLine(to: CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length))
        }
        return path
    }
}

/// Six grey metal blades closing toward the centre (iOS 4 camera open/capture animation).
struct IrisShutter: View {
    var openness: CGFloat

    var body: some View {
        ZStack {
            IrisBladesShape(openness: openness)
                .fill(LinearGradient(colors: [Color(hex: 0x7A7A7A), Color(hex: 0x4A4A4A), Color(hex: 0x2A2A2A)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing),
                      style: FillStyle(eoFill: true))
            IrisSeamsShape(openness: openness)
                .stroke(Color.black.opacity(0.6), lineWidth: 1.5)
            IrisSeamsShape(openness: openness)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
                .offset(x: 1, y: 1)
        }
        .clipped()
    }
}
