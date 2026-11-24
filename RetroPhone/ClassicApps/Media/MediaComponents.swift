import SwiftUI

// MARK: - Formatting

enum MediaFormat {
    /// "3:07" / "1:02:09" style durations (iOS 4 iPod / Voice Memos).
    static func duration(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t.rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Action sheet (iOS 4 black translucent UIActionSheet)

struct RetroSheetButton {
    enum Role { case normal, destructive, cancel }
    var title: String
    var role: Role = .normal
    var action: () -> Void = {}
}

struct RetroActionSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    var title: String?
    var buttons: [RetroSheetButton]

    func body(content: Content) -> some View {
        content.overlay {
            ZStack(alignment: .bottom) {
                if isPresented {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { isPresented = false }
                        .transition(.opacity)
                    VStack(spacing: 10) {
                        if let title {
                            Text(title)
                                .font(.retro(14))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .shadow(color: .black.opacity(0.6), radius: 0, y: -1)
                                .padding(.bottom, 4)
                        }
                        ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                            GlossyButton(title: button.title, tint: tint(for: button.role)) {
                                isPresented = false
                                button.action()
                            }
                            .padding(.top, button.role == .cancel ? 8 : 0)
                        }
                    }
                    .padding(EdgeInsets(top: 16, leading: 20, bottom: 18, trailing: 20))
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(colors: [Color(hex: 0x3C3C3C, opacity: 0.92), Color(hex: 0x060606, opacity: 0.94)],
                                       startPoint: .top, endPoint: .bottom),
                        ignoresSafeAreaEdges: .bottom
                    )
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1) }
                    .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeOut(duration: 0.25), value: isPresented)
        }
    }

    private func tint(for role: RetroSheetButton.Role) -> GlossyButton.Tint {
        switch role {
        case .normal: .gray
        case .destructive: .red
        case .cancel: .black
        }
    }
}

extension View {
    func retroActionSheet(_ title: String? = nil, isPresented: Binding<Bool>, buttons: [RetroSheetButton]) -> some View {
        modifier(RetroActionSheetModifier(isPresented: isPresented, title: title, buttons: buttons))
    }
}

// MARK: - Misc

/// Pinstripe-backed permission placeholder for apps whose own background is dark.
struct MediaPermissionView: View {
    var systemImage: String
    var title: String
    var message: String
    var requestTitle: String? = nil
    var request: (() -> Void)? = nil
    var denied: Bool = false

    var body: some View {
        PermissionPlaceholder(systemImage: systemImage, title: title, message: message,
                              requestTitle: requestTitle, request: request, denied: denied)
            .background(PinstripeBackground().ignoresSafeArea())
    }
}

/// Fine horizontal grain used for the iOS 4 brushed-metal / dark chrome bars.
struct BrushedMetalTexture: View {
    var lineAlpha: Double = 0.06
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt32 = 0x2545F491
            var y: CGFloat = 0
            while y < size.height {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let r = Double(seed >> 8) / Double(1 << 24)
                let color: Color = r > 0.5 ? .white.opacity(lineAlpha * (r - 0.5) * 2) : .black.opacity(lineAlpha * (0.5 - r) * 2)
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(color))
                y += 1
            }
        }
        .allowsHitTesting(false)
    }
}
