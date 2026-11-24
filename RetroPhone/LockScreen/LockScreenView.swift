import SwiftUI

/// Virtual iOS 4 lock screen. This is an in-app screen only — it is NOT a security feature and
/// does not interact with the device passcode / Face ID.
struct LockScreenView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.deviceInsets) private var insets
    @State private var departing = false

    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width / 320, 1.4)
            let now = ClockTicker.shared.now
            ZStack {
                WallpaperView(choice: SettingsStore.shared.value.lockWallpaper)
                    .opacity(departing ? 0 : 1)

                if BatteryMonitor.shared.isCharging {
                    ChargingBattery(scale: k)
                        .opacity(departing ? 0 : 1)
                }

                VStack(spacing: 0) {
                    // Top clock panel
                    VStack(spacing: 2 * k) {
                        Text(RetroFormat.lockTime(now))
                            .font(.custom("HelveticaNeue-Light", fixedSize: 62 * k))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 0, y: -1)
                            .accessibilityIdentifier("lockTime")
                        Text(RetroFormat.lockDate(now))
                            .font(.retroFixed(16 * k, .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 0, y: -1)
                    }
                    .padding(.top, insets.top + 4 * k)
                    .padding(.bottom, 10 * k)
                    .frame(maxWidth: .infinity)
                    .background(LockPanel(top: true))
                    .offset(y: departing ? -(insets.top + 140 * k) : 0)

                    Spacer()

                    // Bottom slider panel
                    SlideToUnlock(scale: k) { unlock() }
                        .id(router.lockGeneration)
                        .padding(.top, 20 * k)
                        .padding(.bottom, max(insets.bottom, 12) + 8 * k)
                        .frame(maxWidth: .infinity)
                        .background(LockPanel(top: false))
                        .offset(y: departing ? 140 * k + insets.bottom : 0)
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: router.lockGeneration) { departing = false }
    }

    private func unlock() {
        SoundService.shared.play(.unlock)
        Haptics.tap(.rigid)
        withAnimation(.timingCurve(0.5, 0, 0.75, 1, duration: 0.3)) { departing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            router.unlocked()
            departing = false
        }
    }
}

/// Translucent black glass panel used for the top and bottom lock bars.
private struct LockPanel: View {
    var top: Bool
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black.opacity(0.42), Color.black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                if !top { Rectangle().fill(Color.white.opacity(0.28)).frame(height: 1) }
                LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                    .frame(maxHeight: .infinity)
                Color.clear.frame(maxHeight: .infinity)
                if top { Rectangle().fill(Color.white.opacity(0.22)).frame(height: 1) }
            }
        }
    }
}

/// The slider: draggable knob in a recessed track, shimmering label.
struct SlideToUnlock: View {
    var scale: CGFloat
    var onUnlock: () -> Void
    @State private var offset: CGFloat = 0
    @State private var done = false

    var body: some View {
        let trackW = 288 * scale, trackH = 52 * scale
        let knobW = 80 * scale, knobH = 46 * scale
        let maxX = trackW - knobW - 6 * scale
        let progress = maxX > 0 ? offset / maxX : 0

        ZStack(alignment: .leading) {
            // Recessed track
            RoundedRectangle(cornerRadius: 11 * scale, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x050505, opacity: 0.85), Color(hex: 0x2A2A2A, opacity: 0.75)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 11 * scale, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 1).offset(y: 1).mask(RoundedRectangle(cornerRadius: 11 * scale)))
                .overlay(RoundedRectangle(cornerRadius: 11 * scale, style: .continuous).stroke(Color.black.opacity(0.8), lineWidth: 1))

            ShimmerText(text: L("밀어서 잠금 해제"), size: 22 * scale)
                .frame(width: trackW - knobW, alignment: .center)
                .offset(x: knobW + 2 * scale)
                .opacity(max(0, 1 - progress * 2.2))
                .accessibilityHidden(true)

            // Knob
            ZStack {
                RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                    .fill(LinearGradient(stops: [
                        .init(color: Color(hex: 0xFFFFFF), location: 0),
                        .init(color: Color(hex: 0xE4E4E4), location: 0.5),
                        .init(color: Color(hex: 0xC9C9C9), location: 0.5),
                        .init(color: Color(hex: 0xB0B0B0), location: 1),
                    ], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 9 * scale, style: .continuous).stroke(Color(hex: 0x6A6A6A), lineWidth: 1))
                Image(systemName: "arrow.right")
                    .font(.system(size: 24 * scale, weight: .heavy))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0x9A9A9A), Color(hex: 0x6E6E6E)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .white, radius: 0, y: 1)
            }
            .frame(width: knobW, height: knobH)
            .offset(x: 3 * scale + offset)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard !done else { return }
                        offset = min(max(0, v.translation.width), maxX)
                    }
                    .onEnded { _ in
                        guard !done else { return }
                        if offset >= maxX * 0.94 {
                            done = true
                            offset = maxX
                            onUnlock()
                        } else {
                            withAnimation(.timingCurve(0.3, 0, 0.3, 1, duration: 0.3)) { offset = 0 }
                        }
                    }
            )
        }
        .frame(width: trackW, height: trackH)
        .accessibilityElement()
        .accessibilityLabel(L("밀어서 잠금 해제"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("unlockSlider")
        .accessibilityAction { done = true; onUnlock() }
    }
}

/// The famous sweeping highlight across the label.
struct ShimmerText: View {
    var text: String
    var size: CGFloat
    @State private var phase: CGFloat = -1

    var body: some View {
        let label = Text(text).font(.custom("Helvetica", fixedSize: size))
        label
            .foregroundStyle(Color.white.opacity(0.42))
            .overlay {
                GeometryReader { g in
                    label
                        .foregroundStyle(.white)
                        .frame(width: g.size.width, height: g.size.height)
                        .mask(
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white, location: 0.5),
                                .init(color: .clear, location: 1),
                            ], startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width * 0.45)
                            .offset(x: phase * g.size.width * 1.2)
                            .frame(width: g.size.width, alignment: .leading)
                        )
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .onAppear {
                phase = -0.45
                withAnimation(.linear(duration: 2.2).delay(0.4).repeatForever(autoreverses: false)) { phase = 1.0 }
            }
    }
}

/// Large battery shown on the lock screen while charging (real level).
private struct ChargingBattery: View {
    var scale: CGFloat
    var body: some View {
        let level = BatteryMonitor.shared.level ?? 0
        VStack(spacing: 10 * scale) {
            HStack(spacing: 3 * scale) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12 * scale)
                        .fill(Color.black.opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: 12 * scale).stroke(Color.white.opacity(0.85), lineWidth: 3 * scale))
                        .frame(width: 150 * scale, height: 70 * scale)
                    RoundedRectangle(cornerRadius: 7 * scale)
                        .fill(LinearGradient(colors: [Color(hex: 0x9AF28A), Color(hex: 0x2EB82A)], startPoint: .top, endPoint: .bottom))
                        .frame(width: max(8, 136 * scale * level), height: 56 * scale)
                        .padding(.leading, 7 * scale)
                }
                RoundedRectangle(cornerRadius: 3 * scale).fill(Color.white.opacity(0.85)).frame(width: 8 * scale, height: 24 * scale)
            }
            if let p = BatteryMonitor.shared.percent {
                Text("\(p)%").font(.retroFixed(18 * scale, .bold)).foregroundStyle(.white).shadow(color: .black, radius: 0, y: -1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("충전 중"))
    }
}
