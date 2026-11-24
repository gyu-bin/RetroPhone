import Foundation
import Observation
import UIKit
import WebKit

// MARK: - Search engine

enum SearchEngine: String, CaseIterable, Identifiable {
    case naver, google, duckDuckGo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .naver: L("네이버")
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        }
    }

    func searchURL(for query: String) -> URL {
        let (base, param): (String, String) = switch self {
        case .naver: ("https://search.naver.com/search.naver", "query")
        case .google: ("https://www.google.com/search", "q")
        case .duckDuckGo: ("https://duckduckgo.com/", "q")
        }
        var comps = URLComponents(string: base)!
        comps.queryItems = [URLQueryItem(name: param, value: query)]
        // URLComponents leaves "+" (and "&"/"=" are handled) unescaped in query values; "+" would mean space.
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return comps.url ?? URL(string: base)!
    }

    private static let defaultsKey = "browser.searchEngine"

    /// User-selected engine, persisted in UserDefaults (default: 네이버).
    static var current: SearchEngine {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(SearchEngine.init(rawValue:)) ?? .naver }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

// MARK: - Smart address parsing (pure, unit-testable)

enum BrowserURL {
    /// Turns what the user typed into a URL:
    /// - "https://…" / "http://…" → as is (invalid characters percent-encoded)
    /// - "example.com", "naver.com/path?q=1", "localhost:8080", "192.168.0.1" → "https://" prepended
    /// - anything else (spaces, no dot, unknown shape) → a search with `engine`
    static func resolve(_ input: String, engine: SearchEngine) -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return URL(string: "about:blank")! }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            if let url = makeURL(trimmed), url.host != nil { return url }
            return engine.searchURL(for: trimmed)
        }
        if lower == "about:blank" { return URL(string: "about:blank")! }

        if !trimmed.contains(where: { $0.isWhitespace }) && looksLikeHost(trimmed) {
            if let url = makeURL("https://" + trimmed), url.host != nil { return url }
        }
        return engine.searchURL(for: trimmed)
    }

    /// URL(string:) percent-encodes invalid characters on iOS 17+; fall back to explicit encoding.
    static func makeURL(_ string: String) -> URL? {
        if let url = URL(string: string) { return url }
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.insert(charactersIn: "#")
        guard let encoded = string.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: encoded)
    }

    /// Heuristic: does the start of `s` (before any "/", "?" or "#") look like a host[:port]?
    static func looksLikeHost(_ s: String) -> Bool {
        guard let first = s.first, !"/?#.:".contains(first) else { return false }
        let hostAndPort = String(s.prefix { !"/?#".contains($0) })
        var host = hostAndPort
        if let colon = hostAndPort.lastIndex(of: ":") {
            let port = hostAndPort[hostAndPort.index(after: colon)...]
            guard !port.isEmpty, port.count <= 5, port.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
            host = String(hostAndPort[..<colon])
        }
        if host.lowercased() == "localhost" { return true }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        // IPv4
        if labels.count == 4, labels.allSatisfy({ label in
            guard let n = Int(label), label.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
            return (0...255).contains(n)
        }) { return true }

        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        guard let tld = labels.last, tld.count >= 2, tld.allSatisfy({ $0.isLetter }) else { return false }
        return labels.allSatisfy { label in
            label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } && label.first != "-" && label.last != "-"
        }
    }

    /// Short text for the address field when not editing ("naver.com/…").
    static func displayString(for url: URL?) -> String {
        guard let url, url.absoluteString != "about:blank" else { return "" }
        return url.absoluteString
    }
}

// MARK: - Bookmarks (local JSON via FileStore)

struct BrowserBookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: URL
}

@Observable
final class BrowserBookmarkStore {
    static let shared = BrowserBookmarkStore()
    private static let fileName = "browser-bookmarks.json"

    private(set) var items: [BrowserBookmark]

    private init() {
        items = FileStore.load([BrowserBookmark].self, from: Self.fileName) ?? []
    }

    func add(title: String, url: URL) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        items.append(BrowserBookmark(title: name.isEmpty ? (url.host ?? url.absoluteString) : name, url: url))
        save()
    }

    func contains(_ url: URL?) -> Bool {
        guard let url else { return false }
        return items.contains { $0.url == url }
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func save() { FileStore.save(items, to: Self.fileName) }
}

// MARK: - One page ("tab"): owns its WKWebView and acts as its navigation coordinator

@Observable
final class BrowserTab: NSObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let webView: WKWebView

    private(set) var title = ""
    private(set) var url: URL?
    private(set) var progress: Double = 0
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// Non-nil when the last navigation failed; drives the error page.
    private(set) var loadError: String?
    private(set) var failedURL: URL?
    var snapshot: UIImage?

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        webView = web
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        observations = [
            watch(\.title),
            watch(\.url),
            watch(\.estimatedProgress),
            watch(\.isLoading),
            watch(\.canGoBack),
            watch(\.canGoForward),
        ]
    }

    /// KVO change handlers are @Sendable; WebKit fires them on the main thread, but we hop
    /// to the MainActor explicitly before touching state.
    private func watch<Value>(_ keyPath: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
        webView.observe(keyPath, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in self.syncState() }
        }
    }

    func syncState() {
        title = webView.title ?? ""
        if let u = webView.url { url = u }
        progress = webView.estimatedProgress
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    // MARK: Commands

    func load(_ target: URL) {
        loadError = nil
        failedURL = nil
        guard NetworkMonitor.shared.isOnline || target.isFileURL else {
            url = target
            failedURL = target
            loadError = L("네트워크에 연결되어 있지 않습니다")
            return
        }
        url = target
        webView.load(URLRequest(url: target))
    }

    func reload() {
        if let failed = failedURL ?? (webView.url == nil ? url : nil) {
            load(failed)
        } else {
            loadError = nil
            webView.reload()
        }
    }

    func stop() { webView.stopLoading() }
    func goBack() { loadError = nil; webView.goBack() }
    func goForward() { loadError = nil; webView.goForward() }

    func captureSnapshot() async {
        guard webView.url != nil, webView.bounds.width > 0 else { return }
        if let image = try? await webView.takeSnapshot(configuration: nil) {
            snapshot = image
        }
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let host = url?.host { return host }
        return L("제목 없음")
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadError = nil
        failedURL = nil
        syncState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        syncState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let target = navigationAction.request.url, let scheme = target.scheme?.lowercased() else { return .allow }
        let webSchemes: Set<String> = ["http", "https", "about", "data", "blob", "file", "javascript"]
        if webSchemes.contains(scheme) { return .allow }
        // tel:, mailto:, sms:, maps:, itms-apps:, app schemes… → hand off to iOS.
        if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame?.isMainFrame == true {
            _ = await UIApplication.shared.open(target)
        }
        return .cancel
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func handle(_ error: Error) {
        let ns = error as NSError
        // Cancelled (new navigation started) or interrupted by a policy decision: not a real failure.
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { syncState(); return }
        if ns.domain == "WebKitErrorDomain" && (ns.code == 102 || ns.code == 204) { syncState(); return }
        failedURL = (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? url
        if ns.domain == NSURLErrorDomain && (ns.code == NSURLErrorNotConnectedToInternet || ns.code == NSURLErrorNetworkConnectionLost) {
            loadError = L("네트워크에 연결되어 있지 않습니다")
        } else {
            loadError = ns.localizedDescription
        }
        syncState()
    }

    // MARK: WKUIDelegate

    /// target="_blank" / window.open → open in the same page.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let target = navigationAction.request.url {
            webView.load(URLRequest(url: target))
        }
        return nil
    }
}

// MARK: - Session (pages)

@Observable
final class BrowserSession {
    static let maxTabs = 8

    private(set) var tabs: [BrowserTab]
    var currentID: UUID

    init() {
        let first = BrowserTab()
        tabs = [first]
        currentID = first.id
    }

    var current: BrowserTab { tabs.first { $0.id == currentID } ?? tabs[0] }
    var canAddTab: Bool { tabs.count < Self.maxTabs }

    @discardableResult
    func newTab() -> BrowserTab? {
        guard canAddTab else { return nil }
        let tab = BrowserTab()
        tabs.append(tab)
        currentID = tab.id
        return tab
    }

    func close(_ id: UUID) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closing = tabs[i]
        closing.stop()
        if tabs.count == 1 {
            let fresh = BrowserTab()
            tabs = [fresh]
            currentID = fresh.id
            return
        }
        tabs.remove(at: i)
        if currentID == id { currentID = tabs[min(i, tabs.count - 1)].id }
    }
}
