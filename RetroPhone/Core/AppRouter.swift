import SwiftUI
import Observation

/// Top-level navigation state of the virtual phone ("SpringBoard").
@Observable
final class AppRouter {
    enum Screen: Equatable {
        case setup
        case lock
        case home
        case app(BuiltinApp)
    }

    var screen: Screen
    /// Most-recent-first list of internal apps that are "running" (shown in the multitasking bar).
    var recents: [BuiltinApp] = []
    /// Where the last app launch originated, in unit coordinates of the screen (for zoom animations).
    var launchAnchor: UnitPoint = .center
    var multitaskingVisible = false
    var isEditingHome = false
    var currentPage = 0
    var openFolderID: UUID?
    /// Bumps each time we land on the lock screen so it can reset its slider.
    var lockGeneration = 0
    /// Set by deep links from widgets, e.g. open Calendar on a date.
    var pendingDeepLink: DeepLink?
    /// App to return to after unlocking (restored from a previous session).
    var resumeAfterUnlock: BuiltinApp?

    enum DeepLink: Equatable {
        case calendar(Date)
        case weather
    }

    init(screen: Screen) { self.screen = screen }

    var currentApp: BuiltinApp? { if case .app(let a) = screen { return a }; return nil }

    func open(_ app: BuiltinApp, anchor: UnitPoint = .center) {
        launchAnchor = anchor
        multitaskingVisible = false
        isEditingHome = false
        openFolderID = nil
        recents.removeAll { $0 == app }
        recents.insert(app, at: 0)
        if recents.count > 12 { recents.removeLast(recents.count - 12) }
        withAnimation(RetroMotion.appOpen) { screen = .app(app) }
    }

    /// Single home-button press semantics (iOS 4):
    /// app → home; folder open → close folder; editing → stop editing; multitasking → close; on home page > 0 → page 0.
    func homePressed() {
        if multitaskingVisible {
            withAnimation(RetroMotion.multitask) { multitaskingVisible = false }
            return
        }
        switch screen {
        case .app:
            withAnimation(RetroMotion.appClose) { screen = .home }
        case .home:
            if openFolderID != nil { withAnimation(RetroMotion.folder) { openFolderID = nil } }
            else if isEditingHome { withAnimation(.easeOut(duration: 0.2)) { isEditingHome = false } }
            else if currentPage != 0 { withAnimation(RetroMotion.page) { currentPage = 0 } }
        case .lock, .setup:
            break
        }
    }

    func homeDoublePressed() {
        guard screen != .lock, screen != .setup else { return }
        withAnimation(RetroMotion.multitask) { multitaskingVisible.toggle() }
    }

    func close(_ app: BuiltinApp) {
        recents.removeAll { $0 == app }
        if currentApp == app { withAnimation(RetroMotion.appClose) { screen = .home } }
    }

    func lock() {
        multitaskingVisible = false
        openFolderID = nil
        isEditingHome = false
        lockGeneration += 1
        withAnimation(.easeInOut(duration: 0.3)) { screen = .lock }
    }

    func unlocked() {
        if let app = resumeAfterUnlock {
            resumeAfterUnlock = nil
            withAnimation(RetroMotion.unlock) { screen = .app(app) }
        } else {
            withAnimation(RetroMotion.unlock) { screen = .home }
        }
    }
}

/// Animation curves approximating iOS 4 SpringBoard timing (hand-tuned estimates; not yet
/// verified frame-by-frame against reference recordings — see docs/STATUS.md).
enum RetroMotion {
    static let appOpen = Animation.timingCurve(0.4, 0.0, 0.6, 1.0, duration: 0.38)
    static let appClose = Animation.timingCurve(0.4, 0.0, 0.6, 1.0, duration: 0.34)
    static let unlock = Animation.timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.45)
    static let folder = Animation.timingCurve(0.3, 0.0, 0.3, 1.0, duration: 0.32)
    static let page = Animation.timingCurve(0.2, 0.0, 0.2, 1.0, duration: 0.33)
    static let multitask = Animation.timingCurve(0.3, 0.0, 0.3, 1.0, duration: 0.3)
    static let snapBack = Animation.spring(response: 0.32, dampingFraction: 0.72)
}
