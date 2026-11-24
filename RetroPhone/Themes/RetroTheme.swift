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

/// Design tokens for an OS "era". Only iOS 4 exists today; iOS 5/6 can be added as new values
/// without touching component code (components read `@Environment(\.retroTheme)`).
struct RetroTheme {
    var era: ThemeEra
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
}

private struct RetroThemeKey: EnvironmentKey { static let defaultValue = RetroTheme.ios4 }
extension EnvironmentValues {
    var retroTheme: RetroTheme {
        get { self[RetroThemeKey.self] }
        set { self[RetroThemeKey.self] = newValue }
    }
}

// MARK: Typography — iOS 4 used Helvetica; Korean falls back to Apple SD Gothic Neo automatically.

enum RetroWeight { case regular, bold }

extension Font {
    static func retro(_ size: CGFloat, _ weight: RetroWeight = .regular) -> Font {
        let scaled = size * SettingsStore.shared.value.textScale
        return .custom(weight == .bold ? "Helvetica-Bold" : "Helvetica", fixedSize: scaled)
    }
    /// Unscaled variant for chrome that must keep its size (status bar, icon labels).
    static func retroFixed(_ size: CGFloat, _ weight: RetroWeight = .regular) -> Font {
        .custom(weight == .bold ? "Helvetica-Bold" : "Helvetica", fixedSize: size)
    }
}

extension View {
    /// The classic engraved/embossed text look: a 1pt offset shadow.
    func embossed(_ color: Color = .white.opacity(0.7), y: CGFloat = 1) -> some View {
        shadow(color: color, radius: 0, x: 0, y: y)
    }
}
