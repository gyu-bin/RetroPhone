import UIKit

/// Launches third-party apps through public mechanisms only: registered URL schemes and
/// universal links. RetroPhone cannot enumerate installed apps, read their badges or alter their UI.
enum ExternalAppLauncher {
    enum Availability { case installed, notInstalled, unknown }

    /// `canOpenURL` only answers for schemes declared in LSApplicationQueriesSchemes (Info.plist).
    static func availability(of app: ExternalApp) -> Availability {
        guard let scheme = app.scheme, let url = URL(string: scheme) else { return .unknown }
        return UIApplication.shared.canOpenURL(url) ? .installed : .notInstalled
    }

    /// Tries the app scheme first, then the universal/web link (which opens the app when the
    /// vendor supports universal links, otherwise Safari). Returns false only if nothing opened.
    @discardableResult
    static func open(_ app: ExternalApp) async -> Bool {
        if let scheme = app.scheme, let url = URL(string: scheme) {
            if await UIApplication.shared.open(url) { return true }
        }
        if let web = app.webURL, let url = URL(string: web) {
            return await UIApplication.shared.open(url)
        }
        return false
    }

    /// Catalog apps whose URL scheme iOS reports as openable. Only the ≤50 schemes declared in
    /// LSApplicationQueriesSchemes can be checked; the result never leaves the device.
    static func installedCatalogApps() -> [ExternalApp] {
        let probed = Set(AppCatalog.probedSchemes)
        return AppCatalog.externalApps.filter { app in
            guard app.isSystem != true, let scheme = app.scheme, let url = URL(string: scheme),
                  let root = url.scheme, probed.contains(root) else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
    }

    /// Opens the real Apple app instead of RetroPhone's classic version (when the user chose so).
    @discardableResult
    static func openSystemVersion(of app: BuiltinApp) async -> Bool {
        guard let s = app.systemURL, let url = URL(string: s) else { return false }
        return await UIApplication.shared.open(url)
    }

    static func openAppStore(_ app: ExternalApp) {
        guard let id = app.appStoreID, let url = URL(string: "itms-apps://apps.apple.com/app/id\(id)") else { return }
        UIApplication.shared.open(url)
    }

    /// Validates a user-entered launch URL for a custom app (scheme://… or https://…).
    static func normalizedURL(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let url = URL(string: t.contains("://") ? t : t + "://"),
              let scheme = url.scheme, !scheme.isEmpty,
              scheme.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil else { return nil }
        // Block schemes that would be surprising/unsafe as a home icon.
        if ["javascript", "data", "file"].contains(scheme.lowercased()) { return nil }
        return url.absoluteString
    }
}
