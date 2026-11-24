import SwiftUI

@main
struct RetroPhoneApp: App {
    @State private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundedAt: Date?

    init() {
        LaunchOptions.applyTestOverrides()
        // Alarms/timer notifications must be presented while RetroPhone is in the foreground.
        ClockNotificationDelegate.shared.install()
        let settings = SettingsStore.shared.value
        let initial: AppRouter.Screen = !settings.setupCompleted ? .setup : (settings.lockOnLaunch ? .lock : .home)
        let router = AppRouter(screen: initial)
        RouterPersistence.restore(into: router)
        _router = State(initialValue: router)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(\.retroTheme, .ios4)
                .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = Date()
                LayoutStore.shared.flush()
                RouterPersistence.save(router)
            case .active:
                // Returning from an external app restores the exact home page/state;
                // the virtual lock only shows if auto-lock time elapsed.
                let minutes = SettingsStore.shared.value.autoLockMinutes
                if let at = backgroundedAt, minutes > 0, Date().timeIntervalSince(at) > Double(minutes * 60),
                   router.screen != .setup {
                    router.lock()
                }
                backgroundedAt = nil
                WeatherService.shared.refreshIfNeeded()
            default: break
            }
        }
    }
}

/// Launch arguments used by UI tests / screenshots.
enum LaunchOptions {
    static var isUITest: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }

    static func applyTestOverrides() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-resetState") {
            for f in [LayoutStore.fileName, "settings.json", "router.json", "notes.json"] {
                try? FileManager.default.removeItem(at: FileStore.url(f))
            }
            SettingsStore.shared.reset()
            LayoutStore.shared.layout = .default
        }
        if args.contains("-skipSetup") {
            SettingsStore.shared.value.setupCompleted = true
        }
        if let i = args.firstIndex(of: "-language"), i + 1 < args.count, let lang = AppLanguage(rawValue: args[i + 1]) {
            SettingsStore.shared.value.language = lang
        }
        #if DEBUG
        // Developer/screenshot aid: build the home screen from a screenshot file without the photo picker.
        if let i = args.firstIndex(of: "-importScreenshot"), i + 1 < args.count, let image = UIImage(contentsOfFile: args[i + 1]) {
            SettingsStore.shared.value.homeImportOffered = true
            Task { @MainActor in
                let result = await HomeImportView.buildPages(from: [image])
                LayoutStore.shared.layout = HomeImportView.makeLayout(
                    base: LayoutStore.shared.layout, pages: result.pages,
                    dockApps: [BuiltinApp.phone.appID, BuiltinApp.messages.appID, BuiltinApp.browser.appID, BuiltinApp.settings.appID],
                    keepRealIcons: false, installed: [], keepWidgets: false)
            }
        }
        #endif
    }
}

/// Saves enough router state to come back to the same place after the app is killed.
enum RouterPersistence {
    struct Snapshot: Codable {
        var page: Int
        var recents: [BuiltinApp]
        var openApp: BuiltinApp?
    }

    static func save(_ router: AppRouter) {
        FileStore.save(Snapshot(page: router.currentPage, recents: router.recents, openApp: router.currentApp), to: "router.json")
    }

    static func restore(into router: AppRouter) {
        guard let s = FileStore.load(Snapshot.self, from: "router.json") else { return }
        router.currentPage = max(0, min(s.page, LayoutStore.shared.layout.pages.count - 1))
        router.recents = s.recents
        // If the app was killed inside an internal app, go back into it (behind the lock screen if locked).
        if let app = s.openApp, router.screen == .home { router.screen = .app(app) }
        else if let app = s.openApp, router.screen == .lock { router.resumeAfterUnlock = app }
    }
}
