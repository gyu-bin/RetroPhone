import SwiftUI

/// Layers the home screen, the running internal app and the multitasking tray.
struct SpringboardView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.deviceInsets) private var insets
    static let trayHeight: CGFloat = 112

    var body: some View {
        let settings = SettingsStore.shared.value
        let appOpen = router.currentApp != nil
        let locked = router.screen == .lock
        let shift = router.multitaskingVisible ? -Self.trayHeight : 0

        ZStack(alignment: .bottom) {
            MultitaskingTray()
                .frame(height: Self.trayHeight + insets.bottom)
                .opacity(router.multitaskingVisible ? 1 : 0)
                .ignoresSafeArea(edges: .bottom)

            ZStack {
                WallpaperView(choice: settings.homeWallpaper)

                HomeScreenView()
                    // iOS 4: launching an app flings the icons outward; unlocking flies them in.
                    .scaleEffect(appOpen || locked ? 1.9 : 1)
                    .opacity(appOpen || locked ? 0 : 1)
                    .allowsHitTesting(!appOpen && !locked && !router.multitaskingVisible)

                if let app = router.currentApp {
                    ClassicAppHost(app: app)
                        .id(app)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.08, anchor: router.launchAnchor).combined(with: .opacity),
                            removal: .scale(scale: 0.08, anchor: router.launchAnchor).combined(with: .opacity)))
                        .zIndex(2)
                        .allowsHitTesting(!router.multitaskingVisible)
                }
            }
            .shadow(color: .black.opacity(router.multitaskingVisible ? 0.7 : 0), radius: 6, y: 3)
            .offset(y: shift)
            .overlay {
                if router.multitaskingVisible {
                    // Tapping the shifted-up screen closes the tray, like iOS 4.
                    Color.black.opacity(0.001)
                        .offset(y: shift)
                        .onTapGesture { withAnimation(RetroMotion.multitask) { router.multitaskingVisible = false } }
                }
            }
        }
        .background(Color.black)
    }
}

/// Hosts an internal app. Apps lay out inside the safe area; the root draws the status bar
/// in the top inset and the home button in the bottom inset.
struct ClassicAppHost: View {
    var app: BuiltinApp

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
    }

    @ViewBuilder private var content: some View {
        switch app {
        case .phone: PhoneAppView()
        case .messages: MessagesAppView()
        case .contacts: ContactsAppView()
        case .photos: PhotosAppView()
        case .camera: CameraAppView()
        case .music: MusicAppView()
        case .browser: BrowserAppView()
        case .notes: NotesAppView()
        case .calendar: CalendarAppView()
        case .weather: WeatherAppView()
        case .calculator: CalculatorAppView()
        case .clock: ClockAppView()
        case .maps: MapsAppView()
        case .voiceMemos: VoiceMemosAppView()
        case .settings: SettingsAppView()
        }
    }
}
