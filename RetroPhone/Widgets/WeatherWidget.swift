import SwiftUI

/// Classic 3D weather glyph composed from shapes + symbols.
struct WeatherGlyph: View {
    var condition: WeatherCondition
    var isDay: Bool = true
    var size: CGFloat

    var body: some View {
        ZStack {
            switch condition {
            case .clear:
                if isDay { sun(size) } else { moon(size) }
            case .partlyCloudy:
                (isDay ? AnyView(sun(size * 0.7)) : AnyView(moon(size * 0.7))).offset(x: -size * 0.15, y: -size * 0.15)
                cloud(size * 0.8).offset(x: size * 0.1, y: size * 0.12)
            case .cloudy, .unknown:
                cloud(size * 0.7, dark: true).offset(x: -size * 0.15, y: -size * 0.1)
                cloud(size * 0.85).offset(x: size * 0.08, y: size * 0.08)
            case .fog:
                cloud(size * 0.8, dark: true)
                VStack(spacing: size * 0.06) {
                    ForEach(0..<3, id: \.self) { _ in Capsule().fill(Color.white.opacity(0.8)).frame(width: size * 0.7, height: size * 0.06) }
                }.offset(y: size * 0.3)
            case .drizzle, .rain, .thunder:
                cloud(size * 0.85, dark: condition != .drizzle).offset(y: -size * 0.1)
                HStack(spacing: size * 0.1) {
                    ForEach(0..<(condition == .drizzle ? 2 : 3), id: \.self) { _ in
                        Capsule().fill(LinearGradient(colors: [Color(hex: 0xBFE4FF), Color(hex: 0x3A8BE0)], startPoint: .top, endPoint: .bottom))
                            .frame(width: size * 0.06, height: size * 0.2).rotationEffect(.degrees(15))
                    }
                }.offset(y: size * 0.32)
                if condition == .thunder {
                    Image(systemName: "bolt.fill").font(.system(size: size * 0.3)).foregroundStyle(Color(hex: 0xFFD83A))
                        .shadow(color: .orange, radius: 3).offset(x: size * 0.15, y: size * 0.3)
                }
            case .snow:
                cloud(size * 0.85).offset(y: -size * 0.1)
                HStack(spacing: size * 0.08) {
                    ForEach(0..<3, id: \.self) { _ in Image(systemName: "snowflake").font(.system(size: size * 0.16, weight: .bold)).foregroundStyle(.white) }
                }.offset(y: size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: size * 0.04, y: size * 0.04)
        .accessibilityLabel(L(condition.labelKo))
    }

    private func sun(_ s: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [Color(hex: 0xFFF7B0), Color(hex: 0xFFC21A), Color(hex: 0xF29A00)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: s * 0.45))
            .frame(width: s * 0.7, height: s * 0.7)
            .shadow(color: Color(hex: 0xFFD040).opacity(0.9), radius: s * 0.12)
    }

    private func moon(_ s: CGFloat) -> some View {
        Image(systemName: "moon.fill").resizable().scaledToFit().frame(width: s * 0.6)
            .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFFBE0), Color(hex: 0xE8D27A)], startPoint: .top, endPoint: .bottom))
    }

    private func cloud(_ s: CGFloat, dark: Bool = false) -> some View {
        Image(systemName: "cloud.fill").resizable().scaledToFit().frame(width: s)
            .foregroundStyle(LinearGradient(colors: dark ? [Color(hex: 0xD4DBE4), Color(hex: 0x8C98A8)] : [.white, Color(hex: 0xC9D8E8)],
                                            startPoint: .top, endPoint: .bottom))
    }
}

struct WeatherWidget: View {
    var size: WidgetSize
    var frame: CGSize

    var body: some View {
        let service = WeatherService.shared
        let snap = service.snapshot
        ZStack {
            LinearGradient(colors: snap?.isDay == false ? [Color(hex: 0x24375E), Color(hex: 0x0B1530)] : [Color(hex: 0x5AAEF0), Color(hex: 0x1C56B8)],
                           startPoint: .top, endPoint: .bottom)
            WidgetGloss(strength: 0.3)
            if let snap {
                content(snap)
            } else {
                placeholder(service.status)
            }
        }
        .onAppear { service.refreshIfNeeded() }
    }

    @ViewBuilder
    private func content(_ s: WeatherSnapshot) -> some View {
        let pad: CGFloat = 12
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    EmbossedText(text: s.placeName, size: 15)
                    EmbossedText(text: s.temperature.temperatureString, size: size == .small ? 36 : 42, weight: .regular)
                    EmbossedText(text: "\(L("최고")) \(s.high.temperatureString)  \(L("최저")) \(s.low.temperatureString)", size: 11, weight: .bold)
                }
                Spacer(minLength: 0)
                WeatherGlyph(condition: s.condition, isDay: s.isDay, size: size == .small ? 46 : 64)
            }
            if size != .small {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(s.hourly.prefix(6)) { h in
                        VStack(spacing: 2) {
                            EmbossedText(text: RetroFormat.date(h.time, template: "j"), size: 10)
                            WeatherGlyph(condition: h.condition, isDay: h.isDay, size: 22)
                            EmbossedText(text: h.temperature.temperatureString, size: 12)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.18)))
            }
            if size == .large {
                HStack {
                    Label(s.sunrise.map { RetroFormat.time($0) } ?? "--", systemImage: "sunrise.fill")
                    Spacer()
                    Label(s.sunset.map { RetroFormat.time($0) } ?? "--", systemImage: "sunset.fill")
                }
                .font(.retroFixed(12, .bold)).foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 0, y: -1)
                VStack(spacing: 4) {
                    ForEach(s.daily.prefix(5)) { d in
                        HStack {
                            EmbossedText(text: RetroFormat.date(d.date, template: "EEEE"), size: 13)
                            Spacer()
                            WeatherGlyph(condition: d.condition, size: 22)
                            EmbossedText(text: d.high.temperatureString, size: 13).frame(width: 36, alignment: .trailing)
                            EmbossedText(text: d.low.temperatureString, size: 13, color: Color(hex: 0xBFD8F5)).frame(width: 36, alignment: .trailing)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if size == .small { Spacer(minLength: 0) ; EmbossedText(text: L(s.condition.labelKo), size: 12) }
        }
        .padding(pad)
    }

    @ViewBuilder
    private func placeholder(_ status: WeatherService.Status) -> some View {
        VStack(spacing: 6) {
            WeatherGlyph(condition: .partlyCloudy, size: 40)
            switch status {
            case .locationDenied:
                EmbossedText(text: L("위치 권한이 필요합니다"), size: 12)
                EmbossedText(text: L("설정에서 도시를 지정할 수 있습니다"), size: 10, weight: .regular)
            case .needsPermission:
                EmbossedText(text: L("탭하여 날씨 켜기"), size: 12)
            case .failed(let msg):
                EmbossedText(text: msg, size: 12)
            default:
                EmbossedText(text: L("날씨 불러오는 중…"), size: 12)
            }
        }
        .padding(8)
    }
}
