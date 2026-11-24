import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Design tokens for an OS "era". Components read `@Environment(\.retroTheme)`; where iOS 7's flat
/// look differs in shape (not just colour) they branch on `isFlat`.
struct RetroTheme {
    var era: ThemeEra
    var isFlat: Bool { era == .ios7 }
    // Navigation bar (UINavigationBar default blue-gray)
    var navTop: Color
    var navMid: Color
    var navBottom: Color
    var navBorderTop: Color
    var navBorderBottom: Color
    var navTitleShadow: Color
    // Bar buttons
    var barButtonTop: Color
    var barButtonBottom: Color
    var doneButtonTop: Color
    var doneButtonBottom: Color
    // Grouped table
    var pinstripeBase: Color
    var pinstripeLine: Color
    var cellBorder: Color
    var cellSeparator: Color
    var detailText: Color
    var groupHeaderText: Color
    // Misc
    var tint: Color
    var switchOnTop: Color
    var switchOnBottom: Color
    var dockGlass: Color
    var homeLabelShadow: Color

    static let ios4 = RetroTheme(
        era: .ios4,
        navTop: Color(hex: 0xB4C1D2), navMid: Color(hex: 0x8B9CB5), navBottom: Color(hex: 0x6D84A2),
        navBorderTop: Color(hex: 0xCDD5DF), navBorderBottom: Color(hex: 0x2D3642),
        navTitleShadow: Color(hex: 0x4C5B72),
        barButtonTop: Color(hex: 0x8EA0BA), barButtonBottom: Color(hex: 0x4A6489),
        doneButtonTop: Color(hex: 0x7AA3F2), doneButtonBottom: Color(hex: 0x2D63DA),
        pinstripeBase: Color(hex: 0xC5CCD4), pinstripeLine: Color(hex: 0xCBD2D8),
        cellBorder: Color(hex: 0xA8ABAE), cellSeparator: Color(hex: 0xD9D9D9),
        detailText: Color(hex: 0x385487), groupHeaderText: Color(hex: 0x4C566C),
        tint: Color(hex: 0x2F6BDB),
        switchOnTop: Color(hex: 0x3D7EEB), switchOnBottom: Color(hex: 0x76A6F5),
        dockGlass: Color.white.opacity(0.18), homeLabelShadow: Color.black.opacity(0.9))

    /// iOS 7: white translucent bars, blue text buttons, light gray grouped tables, green switches.
    static let ios7 = RetroTheme(
        era: .ios7,
        navTop: Color(hex: 0xF8F8F8), navMid: Color(hex: 0xF8F8F8), navBottom: Color(hex: 0xF8F8F8),
        navBorderTop: Color(hex: 0xF8F8F8), navBorderBottom: Color(hex: 0xB2B2B2),
        navTitleShadow: .clear,
        barButtonTop: .clear, barButtonBottom: .clear,
        doneButtonTop: Color(hex: 0x007AFF), doneButtonBottom: Color(hex: 0x007AFF),
        pinstripeBase: Color(hex: 0xEFEFF4), pinstripeLine: Color(hex: 0xEFEFF4),
        cellBorder: Color(hex: 0xC8C7CC), cellSeparator: Color(hex: 0xC8C7CC),
        detailText: Color(hex: 0x8E8E93), groupHeaderText: Color(hex: 0x6D6D72),
        tint: Color(hex: 0x007AFF),
        switchOnTop: Color(hex: 0x4CD964), switchOnBottom: Color(hex: 0x4CD964),
        dockGlass: Color.white.opacity(0.3), homeLabelShadow: Color.black.opacity(0.35))

    static func forEra(_ era: ThemeEra) -> RetroTheme { era == .ios7 ? .ios7 : .ios4 }
}

private struct RetroThemeKey: EnvironmentKey { static let defaultValue = RetroTheme.ios4 }
extension EnvironmentValues {
    var retroTheme: RetroTheme {
        get { self[RetroThemeKey.self] }
        set { self[RetroThemeKey.self] = newValue }
    }
}

// MARK: Typography — iOS 4 used Helvetica, iOS 7 Helvetica Neue (lighter weights).
// Korean falls back to Apple SD Gothic Neo automatically.

enum RetroWeight { case regular, bold }

extension Font {
    private static func face(_ weight: RetroWeight) -> String {
        if SettingsStore.shared.value.themeEra == .ios7 {
            return weight == .bold ? "HelveticaNeue-Medium" : "HelveticaNeue"
        }
        return weight == .bold ? "Helvetica-Bold" : "Helvetica"
    }
    static func retro(_ size: CGFloat, _ weight: RetroWeight = .regular) -> Font {
        .custom(face(weight), fixedSize: size * SettingsStore.shared.value.textScale)
    }
    /// Unscaled variant for chrome that must keep its size (status bar, icon labels).
    static func retroFixed(_ size: CGFloat, _ weight: RetroWeight = .regular) -> Font {
        .custom(face(weight), fixedSize: size)
    }
}

extension Font {
    /// iOS 7's system face: Helvetica Neue (UltraLight/Light/Regular/Medium).
    enum NeueWeight: String { case ultraLight = "-UltraLight", light = "-Light", regular = "", medium = "-Medium", bold = "-Bold" }
    static func neue(_ size: CGFloat, _ weight: NeueWeight = .regular) -> Font {
        .custom("HelveticaNeue" + weight.rawValue, fixedSize: size)
    }
}

extension View {
    /// The classic engraved/embossed text look: a 1pt offset shadow (none in the flat iOS 7 look).
    func embossed(_ color: Color = .white.opacity(0.7), y: CGFloat = 1) -> some View {
        modifier(EmbossModifier(color: color, y: y))
    }
}

private struct EmbossModifier: ViewModifier {
    @Environment(\.retroTheme) private var theme
    var color: Color
    var y: CGFloat
    func body(content: Content) -> some View {
        content.shadow(color: theme.isFlat ? .clear : color, radius: 0, x: 0, y: y)
    }
}
