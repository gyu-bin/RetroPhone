import SwiftUI

/// Real iPhone battery level via UIDevice. Apple Watch / AirPods battery levels are not exposed
/// to third-party apps through public API, so the widget states that instead of inventing values.
struct BatteryWidget: View {
    var size: WidgetSize
    var frame: CGSize

    var body: some View {
        let battery = BatteryMonitor.shared
        ZStack {
            LinearGradient(colors: [Color(hex: 0x4A4E55), Color(hex: 0x16181C)], startPoint: .top, endPoint: .bottom)
            WidgetGloss(strength: 0.18)
            if size == .small {
                VStack(spacing: 6) {
                    BatteryGauge(level: battery.level, charging: battery.isCharging, diameter: min(frame.width, frame.height) * 0.62)
                    EmbossedText(text: "iPhone", size: 12)
                }
            } else {
                HStack(spacing: 16) {
                    BatteryGauge(level: battery.level, charging: battery.isCharging, diameter: frame.height * 0.7)
                    VStack(alignment: .leading, spacing: 5) {
                        EmbossedText(text: "iPhone", size: 17)
                        EmbossedText(text: statusText(battery), size: 13, weight: .regular, color: Color(hex: 0xC8CCD2))
                        Spacer().frame(height: 4)
                        Text(L("Apple Watch·AirPods 배터리는 iOS가 다른 앱에 제공하지 않아 표시할 수 없습니다."))
                            .font(.retroFixed(10)).foregroundStyle(Color(hex: 0x9AA0A8))
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private func statusText(_ b: BatteryMonitor) -> String {
        switch b.state {
        case .charging: L("충전 중")
        case .full: L("충전 완료")
        case .unplugged: L("배터리 사용 중")
        case .unknown: L("상태 알 수 없음")
        }
    }
}

/// Classic circular gauge: dark track, colored arc by level, percentage in the middle.
struct BatteryGauge: View {
    var level: Double?
    var charging: Bool
    var diameter: CGFloat

    var body: some View {
        let lv = level ?? 0
        let color: [Color] = lv > 0.5 || charging ? [Color(hex: 0x9CF27C), Color(hex: 0x2EB82A)]
            : lv > 0.2 ? [Color(hex: 0xFFE27A), Color(hex: 0xE8A400)] : [Color(hex: 0xFF8A7A), Color(hex: 0xD8261A)]
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: 0x2A2D32), Color(hex: 0x0A0B0D)], center: .center, startRadius: 0, endRadius: diameter / 2))
            Circle().stroke(Color.black.opacity(0.7), lineWidth: diameter * 0.12)
                .padding(diameter * 0.08)
            Circle().trim(from: 0, to: level == nil ? 0 : max(0.02, lv))
                .stroke(LinearGradient(colors: color, startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: diameter * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(diameter * 0.08)
                .shadow(color: color[1].opacity(0.7), radius: 3)
            Circle().stroke(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            VStack(spacing: 0) {
                if charging { Image(systemName: "bolt.fill").font(.system(size: diameter * 0.16)).foregroundStyle(Color(hex: 0x9CF27C)) }
                Text(level.map { "\(Int(($0 * 100).rounded()))%" } ?? "--")
                    .font(.retroFixed(diameter * 0.22, .bold)).foregroundStyle(.white)
                    .shadow(color: .black, radius: 0, y: -1)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement()
        .accessibilityLabel(level.map { LF("배터리 %d퍼센트", Int(($0 * 100).rounded())) } ?? L("배터리 정보 없음"))
    }
}
