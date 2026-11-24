import SwiftUI

/// Hosts a widget on the home grid with the shared glossy chrome and edit badge.
struct WidgetCell: View {
    @Environment(\.retroTheme) private var theme
    var spec: WidgetSpec
    var size: CGSize
    var editing: Bool
    var onDelete: (() -> Void)? = nil

    var body: some View {
        let radius: CGFloat = theme.isFlat ? 22 : 16
        content
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            // iOS 4 bevel + drop shadow; the flat iOS 7 look has neither.
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.black.opacity(theme.isFlat ? 0 : 0.45), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(theme.isFlat ? 0 : 0.3), lineWidth: 1).padding(1))
            .shadow(color: .black.opacity(theme.isFlat ? 0 : 0.55), radius: 4, y: 3)
            .overlay(alignment: .topLeading) {
                if editing, let onDelete { DeleteBadge(action: onDelete).offset(x: -12, y: -12) }
            }
            .wiggle(editing, seed: spec.kind.rawValue + spec.size.rawValue, amplitude: spec.size == .small ? 1.0 : 0.45)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(LF("%@ 위젯", spec.kind.displayName))
            .accessibilityIdentifier("widget.\(spec.kind.rawValue)")
    }

    @ViewBuilder private var content: some View {
        switch spec.kind {
        case .weather: WeatherWidget(size: spec.size, frame: size)
        case .battery: BatteryWidget(size: spec.size, frame: size)
        case .calendar: CalendarWidget(size: spec.size, frame: size)
        case .analogClock: AnalogClockWidget(size: spec.size, frame: size)
        case .digitalClock: DigitalClockWidget(size: spec.size, frame: size)
        case .photo: PhotoWidget(size: spec.size, frame: size)
        case .notes: NotesWidget(size: spec.size, frame: size)
        case .music: MusicWidget(size: spec.size, frame: size)
        }
    }
}

/// Top-half gloss used on widget faces.
struct WidgetGloss: View {
    @Environment(\.retroTheme) private var theme
    var strength: Double = 0.35
    var body: some View {
        if !theme.isFlat { gloss }
    }
    private var gloss: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.white.opacity(strength), .white.opacity(strength * 0.25)], startPoint: .top, endPoint: .bottom)
                .frame(maxHeight: .infinity)
            Color.clear.frame(maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}

struct EmbossedText: View {
    @Environment(\.retroTheme) private var theme
    var text: String
    var size: CGFloat
    var weight: RetroWeight = .bold
    var color: Color = .white
    var body: some View {
        Text(text)
            .font(theme.isFlat ? .system(size: size, weight: weight == .bold ? .medium : .light) : .retroFixed(size, weight))
            .foregroundStyle(color)
            .shadow(color: .black.opacity(theme.isFlat ? 0 : 0.55), radius: 0, y: -1)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
