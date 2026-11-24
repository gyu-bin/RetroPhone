import SwiftUI

/// Apps can request a status bar style (e.g. Camera = black).
struct StatusBarStyleKey: PreferenceKey {
    static let defaultValue: StatusBarStyle? = nil
    static func reduce(value: inout StatusBarStyle?, nextValue: () -> StatusBarStyle?) {
        value = nextValue() ?? value
    }
}

/// Lets full-screen apps (Camera) hide the virtual status bar.
struct StatusBarHiddenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    func retroStatusBar(_ style: StatusBarStyle) -> some View { preference(key: StatusBarStyleKey.self, value: style) }
    func retroStatusBarHidden(_ hidden: Bool = true) -> some View { preference(key: StatusBarHiddenKey.self, value: hidden) }
}

struct SafeInsetsKey: EnvironmentKey { static let defaultValue = EdgeInsets() }
struct BezelPaddingKey: EnvironmentKey { static let defaultValue = EdgeInsets() }
extension EnvironmentValues {
    /// Device safe-area insets measured at the root (useful inside views that ignore the safe area).
    var deviceInsets: EdgeInsets {
        get { self[SafeInsetsKey.self] }
        set { self[SafeInsetsKey.self] = newValue }
    }
    /// Extra space the classic bezel takes beyond the system safe area (status bar band + chin).
    var bezelPadding: EdgeInsets {
        get { self[BezelPaddingKey.self] }
        set { self[BezelPaddingKey.self] = newValue }
    }
}

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @State private var appStatusStyle: StatusBarStyle?
    @State private var statusHidden = false

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let bezel = SettingsStore.shared.value.classicBezel && router.screen != .setup
            // Classic bezel: the Dynamic Island band becomes a black top bezel, a 20-pt iOS 4 status bar
            // sits below it, and a chin with a large home button fills the bottom.
            let topBezel: CGFloat = bezel ? insets.top : 0
            let statusHeight: CGFloat = bezel ? 20 : insets.top
            let chin: CGFloat = bezel ? max(insets.bottom, 16) + 66 : insets.bottom
            let contentInsets = EdgeInsets(top: topBezel + statusHeight, leading: insets.leading,
                                           bottom: chin, trailing: insets.trailing)
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                Group {
                    switch router.screen {
                    case .setup:
                        SetupFlowView()
                            .transition(.opacity)
                    default:
                        SpringboardView()
                            .onPreferenceChange(StatusBarStyleKey.self) { appStatusStyle = $0 }
                            .onPreferenceChange(StatusBarHiddenKey.self) { statusHidden = $0 }
                        if router.screen == .lock {
                            LockScreenView()
                                .transition(.identity)
                                .zIndex(10)
                        }
                    }
                }
                .environment(\.deviceInsets, contentInsets)
                // UIKit-backed containers (NavigationStack) ignore safeAreaPadding, so apps get explicit padding.
                .environment(\.bezelPadding, EdgeInsets(top: contentInsets.top - insets.top, leading: 0,
                                                         bottom: contentInsets.bottom - insets.bottom, trailing: 0))

                if !(statusHidden && router.currentApp != nil && !router.multitaskingVisible) {
                    Group {
                        if bezel {
                            RetroStatusBar(style: statusStyle, topInset: statusHeight)
                        } else {
                            RetroStatusBar(style: statusStyle, topInset: insets.top)
                                .ignoresSafeArea(edges: .top)
                        }
                    }
                    .zIndex(20)
                    .allowsHitTesting(false)
                }

                if bezel {
                    VStack(spacing: 0) {
                        TopBezel().frame(height: topBezel)
                        Spacer(minLength: 0)
                    }
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                    .zIndex(25)

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        ChinBezel(router: router, systemInset: insets.bottom).frame(height: chin)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .zIndex(30)
                } else if SettingsStore.shared.value.showHomeButton && router.screen != .setup && router.screen != .lock {
                    VStack {
                        Spacer()
                        VirtualHomeButton(router: router)
                            .padding(.bottom, max(0, insets.bottom - 34) / 2)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .zIndex(30)
                }
            }
            .background(IdleTracker())
        }
        .statusBarHidden(true)
        .dynamicTypeSize(.large)
        .onAppear { LayoutStore.shared.layout.normalize() }
    }

    private var statusStyle: StatusBarStyle {
        switch router.screen {
        case .lock, .home: return .translucent
        case .app: return router.multitaskingVisible ? .translucent : (appStatusStyle ?? .gray)
        case .setup: return .gray
        }
    }
}

/// Observes all touches on the window (without intercepting them) to drive the virtual auto-lock.
struct IdleTracker: UIViewRepresentable {
    @Environment(AppRouter.self) private var router

    func makeUIView(context: Context) -> TrackerView {
        let v = TrackerView()
        v.onIdle = { [router] in
            if router.screen != .lock && router.screen != .setup { router.lock() }
        }
        return v
    }
    func updateUIView(_ uiView: TrackerView, context: Context) {}

    final class TrackerView: UIView, UIGestureRecognizerDelegate {
        var onIdle: (() -> Void)?
        private var lastTouch = Date()
        private var timer: Timer?
        private weak var recognizerWindow: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, recognizerWindow !== window else { return }
            recognizerWindow = window
            let r = UILongPressGestureRecognizer(target: self, action: #selector(touched))
            r.minimumPressDuration = 0
            r.cancelsTouchesInView = false
            r.delaysTouchesBegan = false
            r.delaysTouchesEnded = false
            r.delegate = self
            window.addGestureRecognizer(r)
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
        }

        @objc private func touched() { lastTouch = Date() }

        private func check() {
            let minutes = SettingsStore.shared.value.autoLockMinutes
            guard minutes > 0, Date().timeIntervalSince(lastTouch) > Double(minutes * 60) else { return }
            lastTouch = Date()
            onIdle?()
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
    }
}

/// Full-screen modals are separate presentations: hide the iOS status bar there too and draw the
/// classic one in the top inset.
struct RetroModalChrome: ViewModifier {
    var style: StatusBarStyle = .gray
    func body(content: Content) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                content
                RetroStatusBar(style: style, topInset: geo.safeAreaInsets.top)
                    .frame(height: max(20, geo.safeAreaInsets.top))
                    .offset(y: -geo.safeAreaInsets.top)
                    .allowsHitTesting(false)
            }
        }
        .statusBarHidden(true)
    }
}

extension View {
    func retroModalChrome(_ style: StatusBarStyle = .gray) -> some View { modifier(RetroModalChrome(style: style)) }
}

extension View {
    /// iOS 4-style modal: slides up full screen (no card sheet) with the classic status bar.
    func retroSheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                   @ViewBuilder content: @escaping () -> Content) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) { content().retroModalChrome() }
    }

    func retroSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                       @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        fullScreenCover(item: item, onDismiss: onDismiss) { content($0).retroModalChrome() }
    }
}

/// Black glass top bezel (covers the Dynamic Island band).
struct TopBezel: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(hex: 0x1A1A1C), Color(hex: 0x050505)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

/// iPhone 4-style chin with a large home button. The system home indicator stays visible below
/// the button, so the iOS home gesture is never blocked.
struct ChinBezel: View {
    var router: AppRouter
    var systemInset: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x050505), Color(hex: 0x17171A)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VirtualHomeButton(router: router, size: 56)
                Spacer(minLength: 0)
                Color.clear.frame(height: systemInset * 0.75)
            }
        }
    }
}
