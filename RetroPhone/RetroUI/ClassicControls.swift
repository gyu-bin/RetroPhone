import SwiftUI

// MARK: - Pinstripe background (UITableView grouped style)

struct PinstripeBackground: View {
    @Environment(\.retroTheme) private var theme
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.pinstripeBase))
            var x: CGFloat = 0
            while x < size.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 3, height: size.height)), with: .color(theme.pinstripeLine))
                x += 7
            }
        }
        .drawingGroup()
    }
}

// MARK: - Grouped table

/// A grouped-style section: optional header/footer and a white rounded card with separators.
struct GroupedSection<Content: View>: View {
    @Environment(\.retroTheme) private var theme
    var header: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        if theme.isFlat { flatBody } else { classicBody }
    }

    /// iOS 7: small gray header, edge-to-edge white rows with inset hairlines.
    private var flatBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let header {
                Text(header)
                    .font(.neue(14))
                    .foregroundStyle(theme.groupHeaderText)
                    .padding(.horizontal, 15)
            }
            VStack(spacing: 0) {
                Group(subviews: content()) { subviews in
                    ForEach(subviews.indices, id: \.self) { i in
                        subviews[i].padding(.horizontal, 5)
                        if i < subviews.count - 1 {
                            Rectangle().fill(theme.cellSeparator).frame(height: 0.5).padding(.leading, 15)
                        }
                    }
                }
            }
            .background(Color.white)
            .overlay(alignment: .top) { Rectangle().fill(theme.cellSeparator).frame(height: 0.5) }
            .overlay(alignment: .bottom) { Rectangle().fill(theme.cellSeparator).frame(height: 0.5) }
            if let footer {
                Text(footer)
                    .font(.neue(14))
                    .foregroundStyle(theme.groupHeaderText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 15)
            }
        }
        .padding(.top, 22)
    }

    private var classicBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header)
                    .font(.retro(17, .bold))
                    .foregroundStyle(theme.groupHeaderText)
                    .embossed()
                    .padding(.horizontal, 20)
            }
            VStack(spacing: 0) {
                Group(subviews: content()) { subviews in
                    ForEach(subviews.indices, id: \.self) { i in
                        subviews[i]
                        if i < subviews.count - 1 {
                            Rectangle().fill(theme.cellSeparator).frame(height: 1)
                        }
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.cellBorder, lineWidth: 1))
            .shadow(color: .white.opacity(0.8), radius: 0, y: 1)
            .padding(.horizontal, 10)
            if let footer {
                Text(footer)
                    .font(.retro(15))
                    .foregroundStyle(theme.groupHeaderText)
                    .embossed()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.top, 10)
    }
}

/// A standard table cell: bold title, optional blue detail, optional chevron.
struct TableRow<Accessory: View>: View {
    @Environment(\.retroTheme) private var theme
    var title: String
    var detail: String? = nil
    var icon: IconArt? = nil
    var systemIcon: String? = nil
    var chevron: Bool = false
    var destructive: Bool = false
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            if let icon { RetroIconView(art: icon, size: 29) }
            if let systemIcon {
                Image(systemName: systemIcon).font(.system(size: 18)).foregroundStyle(theme.detailText).frame(width: 29)
            }
            Text(title)
                .font(.retro(17, theme.isFlat ? .regular : .bold))
                .foregroundStyle(destructive ? (theme.isFlat ? Color(hex: 0xFF3B30) : Color(hex: 0xC8160B)) : .black)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let detail {
                Text(detail).font(.retro(17)).foregroundStyle(theme.detailText).lineLimit(1)
            }
            accessory()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: theme.isFlat ? 13 : 14, weight: theme.isFlat ? .semibold : .bold))
                    .foregroundStyle(theme.isFlat ? Color(hex: 0xC7C7CC) : Color(hex: 0x7F7F7F))
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

extension TableRow where Accessory == EmptyView {
    init(title: String, detail: String? = nil, icon: IconArt? = nil, systemIcon: String? = nil,
         chevron: Bool = false, destructive: Bool = false) {
        self.init(title: title, detail: detail, icon: icon, systemIcon: systemIcon, chevron: chevron,
                  destructive: destructive, accessory: { EmptyView() })
    }
}

/// Plain (non-grouped) list row background, white with a gray hairline, like iOS 4 plain tables.
struct PlainRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            content().frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 10)
            Rectangle().fill(Color(hex: 0xE0E0E0)).frame(height: 1)
        }
        .background(Color.white)
        .contentShape(Rectangle())
    }
}

/// Section header for plain tables (gray gradient bar with embossed white text).
struct PlainSectionHeader: View {
    @Environment(\.retroTheme) private var theme
    var title: String
    var body: some View {
        if theme.isFlat {
            Text(title)
                .font(.neue(15, .medium))
                .foregroundStyle(.black)
                .padding(.horizontal, 15)
                .frame(maxWidth: .infinity, minHeight: 23, alignment: .leading)
                .background(Color(hex: 0xF7F7F7))
        } else {
            classic
        }
    }
    private var classic: some View {
        Text(title)
            .font(.retro(17, .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 0, y: 1)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 23, alignment: .leading)
            .background(LinearGradient(colors: [Color(hex: 0xA5B1BA), Color(hex: 0xB8C1C8)], startPoint: .top, endPoint: .bottom))
    }
}

// MARK: - Toggle (iOS 4 ON/OFF switch)

struct RetroToggle: View {
    @Environment(\.retroTheme) private var theme
    @Binding var isOn: Bool
    var label: String = ""

    var body: some View {
        if theme.isFlat { flatSwitch } else { classicSwitch }
    }

    /// iOS 7 switch: green capsule, white round knob.
    private var flatSwitch: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? theme.switchOnTop : Color.white)
                .overlay(Capsule().stroke(isOn ? theme.switchOnTop : Color(hex: 0xE5E5EA), lineWidth: 1.5))
            Circle().fill(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
                .padding(2)
        }
        .frame(width: 51, height: 31)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.selection()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isOn.toggle() }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? L("켬") : L("끔"))
        .accessibilityAddTraits(.isButton)
    }

    private var classicSwitch: some View {
        let w: CGFloat = 94, h: CGFloat = 27
        return ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                Text(L("켬")).font(.retroFixed(16, .bold)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 0, y: -1)
                    .frame(width: w - h + 2)
                    .background(LinearGradient(colors: [theme.switchOnTop, theme.switchOnBottom], startPoint: .top, endPoint: .bottom))
                Color.clear.frame(width: h - 2)
                Text(L("끔")).font(.retroFixed(16, .bold)).foregroundStyle(Color(hex: 0x8A8A8A))
                    .frame(width: w - h + 2)
                    .background(LinearGradient(colors: [Color(hex: 0xEDEDED), Color(hex: 0xFFFFFF)], startPoint: .top, endPoint: .bottom))
            }
            .frame(height: h)
            .offset(x: isOn ? 0 : -(w - h))
            Circle().fill(.clear).frame(width: 0)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFDFDFD), Color(hex: 0xC8C8C8)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color(hex: 0x8A8A8A), lineWidth: 1))
                .frame(width: h + 12, height: h)
                .offset(x: isOn ? w - h - 12 : 0)
        }
        .frame(width: w, height: h, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color(hex: 0x7A7A7A), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.selection()
            SoundService.shared.play(.tock)
            withAnimation(.easeOut(duration: 0.18)) { isOn.toggle() }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? L("켬") : L("끔"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Segmented control

struct RetroSegmented<T: Hashable>: View {
    @Environment(\.retroTheme) private var theme
    var options: [(T, String)]
    @Binding var selection: T
    var style: BarStyle = .blue

    var body: some View {
        if theme.isFlat { flatBody } else { classicBody }
    }

    /// iOS 7: thin tinted outline, selected segment filled.
    private var flatBody: some View {
        let tint: Color = style == .blue ? theme.tint : .white
        return HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                let selected = option.0 == selection
                Button {
                    Haptics.selection()
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.neue(13))
                        .foregroundStyle(selected ? (style == .blue ? Color.white : Color.black) : tint)
                        .frame(maxWidth: .infinity, minHeight: 29)
                        .background(selected ? tint : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if idx < options.count - 1 { Rectangle().fill(tint).frame(width: 1) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(tint, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var classicBody: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                let selected = option.0 == selection
                Button {
                    Haptics.selection()
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.retroFixed(13, .bold))
                        .foregroundStyle(selected || style != .blue ? .white : Color(hex: 0x4A4A4A))
                        .shadow(color: selected ? .black.opacity(0.4) : .white.opacity(0.8), radius: 0, y: selected ? -1 : 1)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            LinearGradient(colors: selected
                                           ? [theme.doneButtonTop, theme.doneButtonBottom]
                                           : (style == .blue ? [Color(hex: 0xFDFDFD), Color(hex: 0xD3D3D3)] : [Color(hex: 0x6A6A6A), Color(hex: 0x2A2A2A)]),
                                           startPoint: .top, endPoint: .bottom)
                        )
                }
                .buttonStyle(.plain)
                if idx < options.count - 1 { Rectangle().fill(Color(hex: 0x7A7A7A)).frame(width: 1) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(hex: 0x6A6A6A), lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Search bar

struct RetroSearchBar: View {
    @Environment(\.retroTheme) private var theme
    @Binding var text: String
    var placeholder: String = L("검색")
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color(hex: 0x8A8A8A))
            TextField(placeholder, text: $text)
                .font(.retro(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color(hex: 0xA0A0A0))
                }.accessibilityLabel(L("지우기"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: theme.isFlat ? 28 : 30)
        .background {
            if theme.isFlat { RoundedRectangle(cornerRadius: 5).fill(Color.white) }
            else { Capsule().fill(Color.white).overlay(Capsule().stroke(Color(hex: 0x8A96A6), lineWidth: 1)) }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background {
            if theme.isFlat { Color(hex: 0xC9C9CE) }
            else { LinearGradient(colors: [Color(hex: 0xD0D7DF), Color(hex: 0xA8B4C2)], startPoint: .top, endPoint: .bottom) }
        }
    }
}

// MARK: - Glossy button (big rounded, e.g. "Call", "Delete")

struct GlossyButton: View {
    @Environment(\.retroTheme) private var theme
    enum Tint { case green, red, blue, gray, black }
    var title: String
    var systemImage: String? = nil
    var tint: Tint = .blue
    var height: CGFloat = 46
    var action: () -> Void

    private var colors: (Color, Color) {
        switch tint {
        case .green: (Color(hex: 0x6CD65A), Color(hex: 0x1F8E14))
        case .red: (Color(hex: 0xF0645A), Color(hex: 0xB3140B))
        case .blue: (Color(hex: 0x6FA0F5), Color(hex: 0x2559D0))
        case .gray: (Color(hex: 0xF4F4F4), Color(hex: 0xC2C2C2))
        case .black: (Color(hex: 0x5A5A5A), Color(hex: 0x111111))
        }
    }

    private var flatColor: Color {
        switch tint {
        case .green: Color(hex: 0x4CD964)
        case .red: Color(hex: 0xFF3B30)
        case .blue: theme.tint
        case .gray: Color.white
        case .black: Color(hex: 0x1C1C1E)
        }
    }

    var body: some View {
        if theme.isFlat { flatBody } else { classicBody }
    }

    /// iOS 7: flat colour, no gloss; the gray variant is a white button with tinted text.
    private var flatBody: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.neue(18))
            .foregroundStyle(tint == .gray ? theme.tint : .white)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(flatColor))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(tint == .gray ? Color(hex: 0xC8C7CC) : .clear, lineWidth: 0.5))
        }
        .buttonStyle(PressDimStyle())
    }

    private var classicBody: some View {
        Button {
            Haptics.tap()
            SoundService.shared.play(.tock)
            action()
        } label: {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.retro(19, .bold))
            .foregroundStyle(tint == .gray ? Color(hex: 0x333333) : .white)
            .shadow(color: tint == .gray ? .white : .black.opacity(0.45), radius: 0, y: tint == .gray ? 1 : -1)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                ZStack {
                    LinearGradient(colors: [colors.0, colors.1], startPoint: .top, endPoint: .bottom)
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                        Color.clear
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.45), lineWidth: 1))
            .shadow(color: .white.opacity(0.5), radius: 0, y: 1)
        }
        .buttonStyle(PressDimStyle())
    }
}

// MARK: - Permission / empty states

/// Shown when a feature's iOS permission is denied or not yet requested.
struct PermissionPlaceholder: View {
    var systemImage: String
    var title: String
    var message: String
    var requestTitle: String? = nil
    var request: (() -> Void)? = nil
    var denied: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 54))
                .foregroundStyle(Color(hex: 0x7A8494))
                .shadow(color: .white, radius: 0, y: 1)
            Text(title).font(.retro(20, .bold)).foregroundStyle(Color(hex: 0x4C566C)).embossed()
            Text(message).font(.retro(15)).foregroundStyle(Color(hex: 0x4C566C)).multilineTextAlignment(.center).embossed()
            if denied {
                GlossyButton(title: L("설정 열기"), tint: .gray) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .frame(maxWidth: 220)
            } else if let request, let requestTitle {
                GlossyButton(title: requestTitle, tint: .blue, action: request).frame(maxWidth: 220)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Classic alert (blue glass box)

struct RetroAlertButton {
    var title: String
    var isPreferred = false
    var action: () -> Void = {}
}

struct RetroAlertModifier: ViewModifier {
    @Environment(\.retroTheme) private var theme
    @Binding var isPresented: Bool
    var title: String
    var message: String?
    var buttons: [RetroAlertButton]

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                if theme.isFlat { flatAlert } else { classicAlert }
            }
        }
        .animation(.easeOut(duration: 0.18), value: isPresented)
    }

    private func press(_ b: RetroAlertButton) {
        isPresented = false
        b.action()
    }

    /// iOS 7 alert: white frosted panel, hairline-separated blue text buttons.
    private var flatAlert: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text(title).font(.neue(17, .medium)).foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                    if let message {
                        Text(message).font(.neue(14)).foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 19).padding(.bottom, 18)
                Rectangle().fill(Color.black.opacity(0.2)).frame(height: 0.5)
                let stacked = buttons.count > 2
                let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
                layout {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { i, b in
                        if i > 0 {
                            Rectangle().fill(Color.black.opacity(0.2))
                                .frame(width: stacked ? nil : 0.5, height: stacked ? 0.5 : 44)
                        }
                        Button { press(b) } label: {
                            Text(b.title).font(.neue(17, b.isPreferred ? .medium : .regular))
                                .foregroundStyle(theme.tint)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressDimStyle())
                    }
                }
            }
            .frame(width: 270)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(hex: 0xF7F7F7).opacity(0.97)))
            .transition(.scale(scale: 1.2).combined(with: .opacity))
        }
        .zIndex(100)
    }

    private var classicAlert: some View {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 10) {
                        Text(title).font(.retro(18, .bold)).foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 0, y: -1)
                            .multilineTextAlignment(.center)
                        if let message {
                            Text(message).font(.retro(16)).foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 0, y: -1)
                                .multilineTextAlignment(.center)
                        }
                        HStack(spacing: 8) {
                            ForEach(Array(buttons.enumerated()), id: \.offset) { _, b in
                                Button {
                                    SoundService.shared.play(.tock)
                                    isPresented = false
                                    b.action()
                                } label: {
                                    Text(b.title).font(.retro(17, .bold)).foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                        .background(
                                            LinearGradient(colors: b.isPreferred
                                                           ? [Color(hex: 0x8AA8E0), Color(hex: 0x3A5FA8)]
                                                           : [Color(hex: 0x7C8EB4), Color(hex: 0x2E4677)],
                                                           startPoint: .top, endPoint: .bottom)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.5), lineWidth: 1))
                                }
                                .buttonStyle(PressDimStyle())
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(16)
                    .frame(maxWidth: 290)
                    .background(
                        ZStack {
                            LinearGradient(colors: [Color(hex: 0x3E5A8E, opacity: 0.94), Color(hex: 0x14254C, opacity: 0.94)], startPoint: .top, endPoint: .bottom)
                            VStack(spacing: 0) {
                                Ellipse().fill(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                                    .frame(height: 70).scaleEffect(x: 1.6).offset(y: -30)
                                Spacer()
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.85), lineWidth: 2))
                    .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
                    .transition(.scale(scale: 1.15).combined(with: .opacity))
                }
                .zIndex(100)
    }
}

extension View {
    func retroAlert(_ title: String, isPresented: Binding<Bool>, message: String? = nil,
                    buttons: [RetroAlertButton] = [RetroAlertButton(title: L("확인"), isPreferred: true)]) -> some View {
        modifier(RetroAlertModifier(isPresented: isPresented, title: title, message: message, buttons: buttons))
    }
}
