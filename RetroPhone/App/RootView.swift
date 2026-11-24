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
extension EnvironmentValues {
    /// Device safe-area insets measured at the root (useful inside views that ignore the safe area).
    var deviceInsets: EdgeInsets {
        get { self[SafeInsetsKey.self] }
        set { self[SafeInsetsKey.self] = newValue }
    }
}

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @State private var appStatusStyle: StatusBarStyle?
    @State private var statusHidden = false

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

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

                if !(statusHidden && router.currentApp != nil && !router.multitaskingVisible) {
                    RetroStatusBar(style: statusStyle, topInset: insets.top)
                        .ignoresSafeArea(edges: .top)
                        .zIndex(20)
                        .allowsHitTesting(false)
                }

                if SettingsStore.shared.value.showHomeButton && router.screen != .setup && router.screen != .lock {
                    VStack {
                        Spacer()
                        VirtualHomeButton(router: router)
                            .padding(.bottom, max(0, insets.bottom - 34) / 2)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .zIndex(30)
                }
            }
            .environment(\.deviceInsets, insets)
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
