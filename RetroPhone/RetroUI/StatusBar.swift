import SwiftUI

enum StatusBarStyle { case gray, black, translucent }

/// Classic status bar fitted to modern iPhones.
/// - On Dynamic Island / notch devices the center is occupied by hardware, so the time moves to the
///   left "ear" and battery to the right ear, vertically centered on the island.
/// - Only real values are shown: time, battery level/charging, and the network interface type.
///   Carrier name and signal strength are not available via public API and are never displayed.
struct RetroStatusBar: View {
    var style: StatusBarStyle
    var topInset: CGFloat

    private var hasIsland: Bool { topInset >= 44 }
    var height: CGFloat { max(20, topInset) }

    var body: some View {
        let now = ClockTicker.shared.now
        let fg: Color = style == .gray ? Color(hex: 0x1A1A1A) : .white
        ZStack {
            background
            if hasIsland {
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text(RetroFormat.time(now)).font(.retroFixed(15, .bold))
                        NetworkGlyph(color: fg)
                    }
                    .frame(maxWidth: .infinity)
                    Color.clear.frame(width: 130)
                    BatteryGlyph(color: fg).frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .frame(height: topInset * 0.78, alignment: .center)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ZStack {
                    HStack { NetworkGlyph(color: fg); Spacer(); BatteryGlyph(color: fg) }
                    Text(RetroFormat.time(now)).font(.retroFixed(14, .bold))
                }
                .padding(.horizontal, 6)
            }
        }
        .foregroundStyle(fg)
        .shadow(color: style == .gray ? .white.opacity(0.6) : .clear, radius: 0, y: 1)
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(now))
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .gray:
            LinearGradient(colors: [Color(hex: 0xD6D6D6), Color(hex: 0xA4A4A4)], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0x5A5A5A)).frame(height: 1) }
        case .black:
            Color.black
        case .translucent:
            Color.black.opacity(0.5)
        }
    }

    private func accessibilityText(_ now: Date) -> String {
        var parts = [RetroFormat.time(now)]
        if let p = BatteryMonitor.shared.percent { parts.append(LF("배터리 %d퍼센트", p)) }
        return parts.joined(separator: ", ")
    }
}

struct NetworkGlyph: View {
    var color: Color
    var body: some View {
        let net = NetworkMonitor.shared
        Group {
            switch net.kind {
            case .wifi: Image(systemName: "wifi")
            case .cellular: Image(systemName: "antenna.radiowaves.left.and.right")
            case .wired: Image(systemName: "cable.connector")
            case .other: EmptyView()
            case .none: Text(L("오프라인")).font(.retroFixed(11, .bold))
            }
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(color)
    }
}

/// Classic horizontal battery with nub, level fill and lightning bolt while charging.
struct BatteryGlyph: View {
    var color: Color
    var body: some View {
        let battery = BatteryMonitor.shared
        let level = battery.level ?? 1
        HStack(spacing: 3) {
            if SettingsStore.shared.value.showBatteryPercentage, let p = battery.percent {
                Text("\(p)%").font(.retroFixed(12, .bold))
            }
            HStack(spacing: 1) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).stroke(color, lineWidth: 1).frame(width: 23, height: 11)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(level <= 0.2 && !battery.isCharging ? Color(hex: 0xFF3B30) : color)
                        .frame(width: max(1.5, 19 * level), height: 7)
                        .padding(.leading, 2)
                    if battery.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(color == .white ? Color.black : .white)
                            .frame(width: 23)
                    }
                }
                RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Virtual home button

/// Floating home button that sits in the bottom safe-area band (the "chin").
/// One press = home, two presses = multitasking. System gestures are never blocked.
struct VirtualHomeButton: View {
    var router: AppRouter
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0x0A0A0A), Color(hex: 0x3A3A3A)], startPoint: .top, endPoint: .bottom))
            Circle().stroke(LinearGradient(colors: [Color(hex: 0x1A1A1A), Color(hex: 0x6A6A6A)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            RoundedRectangle(cornerRadius: size * 0.085, style: .continuous)
                .stroke(Color(hex: 0xBDBDBD), lineWidth: max(1.2, size * 0.04))
                .frame(width: size * 0.34, height: size * 0.34)
        }
        .frame(width: size, height: size)
        .shadow(color: .white.opacity(0.25), radius: 0, y: 1)
        .opacity(0.9)
        .frame(width: max(60, size + 24), height: max(34, size + 8))
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2).onEnded {
                Haptics.tap(.medium)
                router.homeDoublePressed()
            }
            .exclusively(before: TapGesture(count: 1).onEnded {
                Haptics.tap(.medium)
                SoundService.shared.play(.tock)
                router.homePressed()
            })
        )
        .accessibilityElement()
        .accessibilityLabel(L("홈 버튼"))
        .accessibilityHint(L("한 번 누르면 홈 화면, 두 번 누르면 멀티태스킹"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("homeButton")
        .accessibilityAction { router.homePressed() }
    }
}
