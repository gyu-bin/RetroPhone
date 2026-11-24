import SwiftUI

@main
struct RetroPhoneApp: App {
    @State private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundedAt: Date?

    init() {
        LaunchOptions.applyTestOverrides()
        CameraLook.migrateDefaultOnce()
        // Alarms/timer notifications must be presented while RetroPhone is in the foreground.
        ClockNotificationDelegate.shared.install()
        let settings = SettingsStore.shared.value
        let initial: AppRouter.Screen = !settings.setupCompleted ? .setup : (settings.lockOnLaunch ? .lock : .home)
        let router = AppRouter(screen: initial)
        RouterPersistence.restore(into: router)
        #if DEBUG
        // Developer aid: start inside one app (e.g. `-openApp camera`), skipping lock and home.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-openApp"), i + 1 < args.count, let app = BuiltinApp(rawValue: args[i + 1]) {
            router.screen = .app(app)
        }
        #endif
        _router = State(initialValue: router)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(\.retroTheme, RetroTheme.forEra(SettingsStore.shared.value.themeEra))
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
        if let i = args.firstIndex(of: "-theme"), i + 1 < args.count, let era = ThemeEra(rawValue: args[i + 1]) {
            StyleSettingsView.apply(era)
        }
        #if DEBUG
        // Developer/screenshot aid: build the home screen from a screenshot file without the photo picker.
        if let i = args.firstIndex(of: "-importScreenshot"), i + 1 < args.count, let image = UIImage(contentsOfFile: args[i + 1]) {
            SettingsStore.shared.value.homeImportOffered = true
            // Optional comma-separated folder names, in reading order (OCR can't read emoji names).
            let folderNames = args.firstIndex(of: "-importFolderNames").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }?
                .split(separator: ",").map(String.init) ?? []
            Task { @MainActor in
                var result = await HomeImportView.buildPages(from: [image])
                var n = 0
                for p in result.pages.indices {
                    for i in result.pages[p].items.indices where result.pages[p].items[i].isFolder {
                        if n < folderNames.count { result.pages[p].items[i].label = folderNames[n] }
                        n += 1
                    }
                }
                LayoutStore.shared.layout = HomeImportView.makeLayout(
                    base: LayoutStore.shared.layout, pages: result.pages,
                    dockApps: [BuiltinApp.phone.appID, BuiltinApp.messages.appID, BuiltinApp.browser.appID, BuiltinApp.settings.appID],
                    keepRealIcons: false, installed: [], keepWidgets: false)
                LayoutStore.shared.flush()
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
