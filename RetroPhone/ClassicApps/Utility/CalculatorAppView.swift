import SwiftUI

/// iOS 4 style calculator: light LCD-like display, glossy gray keys, tall "=" key.
struct CalculatorAppView: View {
    @State private var engine = CalculatorEngine()

    var body: some View {
        VStack(spacing: 0) {
            display
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 12)
            keypad
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(hex: 0x3A3D42), Color(hex: 0x16171A)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .retroStatusBar(.black)
    }

    // MARK: Display

    private var display: some View {
        let text = engine.displayText(errorText: L("오류"))
        return ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xB9C4B2), Color(hex: 0xDCE4D6), Color(hex: 0xEEF3EA)],
                                     startPoint: .top, endPoint: .bottom))
            // Inner shadow at the top edge, like a recessed LCD window.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 2)
            VStack(spacing: 0) {
                HStack {
                    Text("M")
                        .font(.retroFixed(14, .bold))
                        .foregroundStyle(Color(hex: 0x2F3A2C))
                        .opacity(engine.hasMemory ? 1 : 0)
                        .accessibilityHidden(!engine.hasMemory)
                    Spacer()
                }
                Text(text)
                    .font(.retroFixed(58, .bold))
                    .foregroundStyle(Color(hex: 0x1F261D))
                    .shadow(color: .white.opacity(0.7), radius: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentTransition(.identity)
                    .accessibilityLabel(text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(height: 104)
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1).offset(y: 1))
        .contextMenu {
            Button {
                if !engine.isError {
                    UIPasteboard.general.string = engine.displayText().replacingOccurrences(of: ",", with: "")
                }
            } label: { Label(L("복사"), systemImage: "doc.on.doc") }
        }
    }

    // MARK: Keypad

    private var keypad: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let cols: CGFloat = 4
            let rows: CGFloat = 6
            let w = (geo.size.width - spacing * (cols - 1)) / cols
            let h = min(72, (geo.size.height - spacing * (rows - 1)) / rows)
            VStack(spacing: spacing) {
                Spacer(minLength: 0)
                HStack(spacing: spacing) {
                    key("mc", .memory, w, h, .memoryClear, label: L("메모리 지우기"))
                    key("m+", .memory, w, h, .memoryAdd, label: L("메모리 더하기"))
                    key("m−", .memory, w, h, .memorySubtract, label: L("메모리 빼기"))
                    key("mr", .memory, w, h, .memoryRecall, label: L("메모리 불러오기"))
                }
                HStack(spacing: spacing) {
                    key(engine.showsAllClear ? "AC" : "C", .function, w, h, .clear,
                        label: engine.showsAllClear ? L("모두 지우기") : L("지우기"))
                    key("±", .function, w, h, .sign, label: L("부호 바꾸기"))
                    key("÷", .op, w, h, .op(.divide), label: L("나누기"))
                    key("×", .op, w, h, .op(.multiply), label: L("곱하기"))
                }
                HStack(spacing: spacing) {
                    digit(7, w, h)
                    digit(8, w, h)
                    digit(9, w, h)
                    key("−", .op, w, h, .op(.subtract), label: L("빼기"))
                }
                HStack(spacing: spacing) {
                    digit(4, w, h)
                    digit(5, w, h)
                    digit(6, w, h)
                    key("+", .op, w, h, .op(.add), label: L("더하기"))
                }
                HStack(alignment: .top, spacing: spacing) {
                    VStack(spacing: spacing) {
                        HStack(spacing: spacing) {
                            digit(1, w, h)
                            digit(2, w, h)
                            digit(3, w, h)
                        }
                        HStack(spacing: spacing) {
                            key("0", .digit, w * 2 + spacing, h, .digit(0), label: "0")
                            key(".", .digit, w, h, .decimal, label: L("소수점"))
                        }
                    }
                    key("=", .equals, w, h * 2 + spacing, .equals, label: L("계산"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func digit(_ d: Int, _ w: CGFloat, _ h: CGFloat) -> some View {
        key(String(d), .digit, w, h, .digit(d), label: String(d))
    }

    private func key(_ title: String, _ style: CalculatorKey.Style, _ w: CGFloat, _ h: CGFloat,
                     _ k: CalculatorEngine.Key, label: String) -> some View {
        var highlighted = false
        if case .op(let o) = k { highlighted = engine.highlightedOp == o }
        return CalculatorKey(title: title, style: style, highlighted: highlighted, accessibility: label) {
            engine.press(k)
        }
        .frame(width: max(0, w), height: max(0, h))
    }
}

/// One glossy calculator key.
private struct CalculatorKey: View {
    enum Style { case digit, op, function, memory, equals }
    var title: String
    var style: Style
    var highlighted: Bool = false
    var accessibility: String
    var action: () -> Void

    private var colors: (Color, Color) {
        switch style {
        case .digit: (Color(hex: 0xF4F4F4), Color(hex: 0xC4C6C9))
        case .op, .function: (Color(hex: 0x8A9099), Color(hex: 0x4D535C))
        case .memory: (Color(hex: 0x6E737A), Color(hex: 0x3A3E44))
        case .equals: (Color(hex: 0xF7A23B), Color(hex: 0xD4630B))
        }
    }

    private var textColor: Color { style == .digit ? Color(hex: 0x2A2C30) : .white }

    var body: some View {
        Button {
            SoundService.shared.play(.keyClick)
            Haptics.tap()
            action()
        } label: {
            GeometryReader { geo in
                ZStack {
                    LinearGradient(colors: [colors.0, colors.1], startPoint: .top, endPoint: .bottom)
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                            .frame(height: min(geo.size.height / 2, 36))
                        Spacer(minLength: 0)
                    }
                    Text(title)
                        .font(.retroFixed(style == .memory ? 22 : (style == .digit ? 32 : 30), .bold))
                        .foregroundStyle(textColor)
                        .shadow(color: style == .digit ? .white : .black.opacity(0.5), radius: 0, y: style == .digit ? 1 : -1)
                        .minimumScaleFactor(0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(highlighted ? Color.white : Color.black.opacity(0.7), lineWidth: highlighted ? 2.5 : 1)
                )
                .shadow(color: .white.opacity(0.18), radius: 0, y: 1)
            }
        }
        .buttonStyle(CalculatorKeyPressStyle())
        .accessibilityLabel(accessibility)
    }
}

private struct CalculatorKeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.22 : 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
