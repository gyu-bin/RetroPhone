import SwiftUI

/// Layers the home screen, the running internal app and the multitasking tray.
struct SpringboardView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.deviceInsets) private var insets
    @Environment(\.bezelPadding) private var bezelPadding
    static let trayHeight: CGFloat = 112

    var body: some View {
        let settings = SettingsStore.shared.value
        let appOpen = router.currentApp != nil
        let locked = router.screen == .lock
        let shift = router.multitaskingVisible ? -Self.trayHeight : 0
        let bezel = bezelPadding.bottom > 0

        ZStack(alignment: .bottom) {
            Group {
                if bezel {
                    // Classic chin: the tray sits directly above it.
                    MultitaskingTray()
                        .frame(height: Self.trayHeight)
                        .padding(.bottom, bezelPadding.bottom)
                } else {
                    MultitaskingTray()
                        .frame(height: Self.trayHeight + insets.bottom)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .opacity(router.multitaskingVisible ? 1 : 0)

            ZStack {
                WallpaperView(choice: settings.homeWallpaper)

                HomeScreenView()
                    // iOS 4: launching an app flings the icons outward; unlocking flies them in.
                    .scaleEffect(appOpen || locked ? 1.9 : 1)
                    .opacity(appOpen || locked ? 0 : 1)
                    .allowsHitTesting(!appOpen && !locked && !router.multitaskingVisible)
                    .accessibilityHidden(appOpen || locked)

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
            // With the chin, the screen ends at the chin's top edge (the wallpaper must not extend under it,
            // or it would cover the tray when the screen slides up).
            .mask(alignment: .bottom) {
                Rectangle()
                    .frame(height: 6000)
                    .padding(.bottom, bezel ? bezelPadding.bottom : -200)
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
    @Environment(\.bezelPadding) private var bezelPadding

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, bezelPadding.top)
            .padding(.bottom, bezelPadding.bottom)
            // Behind the padding too: an app that hides the status bar (camera, photo viewer)
            // must not show the wallpaper in the status-bar strip.
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
