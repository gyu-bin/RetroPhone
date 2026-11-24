import SwiftUI

// MARK: - Navigation bar

/// iOS 4 UINavigationBar: blue-gray gloss gradient, centered embossed white title, 44pt tall.
struct ClassicNavBar<Leading: View, Trailing: View>: View {
    @Environment(\.retroTheme) private var theme
    var title: String
    var style: BarStyle = .blue
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            BarBackground(style: style)
            Text(title)
                .font(.retroFixed(20, .bold))
                .foregroundStyle(.white)
                .shadow(color: style == .blue ? theme.navTitleShadow : .black, radius: 0, x: 0, y: -1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 90)
            HStack {
                leading()
                Spacer()
                trailing()
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 44)
    }
}

extension ClassicNavBar where Leading == EmptyView, Trailing == EmptyView {
    init(title: String, style: BarStyle = .blue) {
        self.init(title: title, style: style, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

enum BarStyle { case blue, black, blackTranslucent }

struct BarBackground: View {
    @Environment(\.retroTheme) private var theme
    var style: BarStyle = .blue

    var body: some View {
        ZStack(alignment: .top) {
            switch style {
            case .blue:
                LinearGradient(stops: [
                    .init(color: theme.navTop, location: 0),
                    .init(color: theme.navMid, location: 0.5),
                    .init(color: theme.navMid.opacity(0.98), location: 0.5),
                    .init(color: theme.navBottom, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(theme.navBorderTop).frame(height: 1)
                VStack { Spacer(); Rectangle().fill(theme.navBorderBottom).frame(height: 1) }
            case .black, .blackTranslucent:
                LinearGradient(stops: [
                    .init(color: Color(hex: 0x5A5A5A), location: 0),
                    .init(color: Color(hex: 0x2A2A2A), location: 0.5),
                    .init(color: Color(hex: 0x0E0E0E), location: 0.5),
                    .init(color: Color(hex: 0x000000), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .opacity(style == .blackTranslucent ? 0.72 : 1)
                Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1)
            }
        }
    }
}

// MARK: - Bar buttons

struct ClassicBarButton: View {
    @Environment(\.retroTheme) private var theme
    enum Kind { case plain, done, back, destructive }
    var title: String
    var kind: Kind = .plain
    var systemImage: String? = nil
    var barStyle: BarStyle = .blue
    var action: () -> Void

    var body: some View {
        Button {
            SoundService.shared.play(.tock)
            action()
        } label: {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .bold))
                } else {
                    Text(title).font(.retroFixed(12.5, .bold)).lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 0, y: -1)
            .padding(.leading, kind == .back ? 16 : 9)
            .padding(.trailing, 9)
            .frame(minWidth: 50, minHeight: 30)
            .background(background)
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(title)
    }

    private var colors: [Color] {
        switch kind {
        case .done: [theme.doneButtonTop, theme.doneButtonBottom]
        case .destructive: [Color(hex: 0xE8665C), Color(hex: 0xB8160B)]
        default:
            barStyle == .blue ? [theme.barButtonTop, theme.barButtonBottom] : [Color(hex: 0x6A6A6A), Color(hex: 0x1A1A1A)]
        }
    }

    @ViewBuilder private var background: some View {
        let fill = LinearGradient(stops: [
            .init(color: colors[0], location: 0), .init(color: colors[0].mix(with: colors[1], by: 0.5), location: 0.5),
            .init(color: colors[1].mix(with: colors[0], by: 0.15), location: 0.5), .init(color: colors[1], location: 1),
        ], startPoint: .top, endPoint: .bottom)
        if kind == .back {
            BackButtonShape().fill(fill)
                .overlay(BackButtonShape().stroke(Color.black.opacity(0.5), lineWidth: 1))
                .shadow(color: .white.opacity(0.35), radius: 0, y: 1)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.black.opacity(0.5), lineWidth: 1))
                .shadow(color: .white.opacity(0.35), radius: 0, y: 1)
        }
    }
}

/// Left-pointing back button outline.
struct BackButtonShape: Shape {
    func path(in r: CGRect) -> Path {
        let arrow: CGFloat = 12, radius: CGFloat = 5
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + arrow, y: r.minY + 1))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + arrow, y: r.maxY - 1))
        p.closeSubpath()
        return p
    }
}

struct PressDimStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.18 : 0)
    }
}

// MARK: - Toolbar

struct ClassicToolbar<Content: View>: View {
    var style: BarStyle = .blue
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            BarBackground(style: style)
            HStack { content() }.padding(.horizontal, 8)
        }
        .frame(height: 44)
    }
}

/// Plain glyph button for toolbars (white with dark shadow).
struct ToolbarIconButton: View {
    var systemImage: String
    var label: String
    var enabled: Bool = true
    var action: () -> Void
    var body: some View {
        Button {
            SoundService.shared.play(.tock)
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
                .frame(width: 44, height: 40)
                .opacity(enabled ? 1 : 0.4)
        }
        .disabled(!enabled)
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Scaffold

/// Standard classic-app page: nav bar on top, content below. Use inside a NavigationStack;
/// the system navigation bar is hidden so only the classic bar shows.
struct ClassicPage<Content: View, Leading: View, Trailing: View>: View {
    var title: String
    var barStyle: BarStyle = .blue
    var background: AnyView = AnyView(PinstripeBackground())
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ClassicNavBar(title: title, style: barStyle, leading: leading, trailing: trailing)
                .zIndex(1)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Back button that pops the current NavigationStack level.
struct ClassicBackButton: View {
    @Environment(\.dismiss) private var dismiss
    var title: String = L("뒤로")
    var barStyle: BarStyle = .blue
    var body: some View {
        ClassicBarButton(title: title, kind: .back, barStyle: barStyle) { dismiss() }
    }
}
