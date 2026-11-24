import Foundation

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case weather, battery, calendar, analogClock, digitalClock, photo, notes, music
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .weather: L("날씨"); case .battery: L("배터리"); case .calendar: L("캘린더")
        case .analogClock: L("아날로그 시계"); case .digitalClock: L("디지털 시계")
        case .photo: L("사진"); case .notes: L("메모"); case .music: L("음악 재생")
        }
    }
    /// Sizes that make sense for this widget.
    var supportedSizes: [WidgetSize] {
        switch self {
        case .weather, .calendar, .photo, .notes, .music: [.small, .wide, .large]
        case .battery, .digitalClock: [.small, .wide]
        case .analogClock: [.small, .large]
        }
    }
    /// Builtin app opened when the widget is tapped.
    var linkedApp: BuiltinApp? {
        switch self {
        case .weather: .weather; case .calendar: .calendar; case .analogClock, .digitalClock: .clock
        case .photo: .photos; case .notes: .notes; case .music: .music; case .battery: nil
        }
    }
}

enum WidgetSize: String, Codable, CaseIterable, Identifiable {
    case small, wide, large
    var id: String { rawValue }
    var columns: Int { self == .small ? 2 : 4 }
    var rows: Int { self == .large ? 4 : 2 }
    var label: String { "\(columns)×\(rows)" }
}

struct WidgetSpec: Codable, Hashable {
    var kind: WidgetKind
    var size: WidgetSize
}

struct Folder: Codable, Hashable {
    var name: String
    var apps: [AppID]
}

struct HomeItem: Codable, Hashable, Identifiable {
    enum Content: Codable, Hashable {
        case app(AppID)
        case folder(Folder)
        case widget(WidgetSpec)
    }
    var id: UUID
    var content: Content

    init(id: UUID = UUID(), _ content: Content) { self.id = id; self.content = content }
    static func app(_ id: AppID) -> HomeItem { HomeItem(.app(id)) }
    static func widget(_ kind: WidgetKind, _ size: WidgetSize) -> HomeItem { HomeItem(.widget(.init(kind: kind, size: size))) }

    var span: (columns: Int, rows: Int) {
        if case .widget(let w) = content { return (w.size.columns, w.size.rows) }
        return (1, 1)
    }
    var appID: AppID? { if case .app(let id) = content { return id }; return nil }
    var folder: Folder? { if case .folder(let f) = content { return f }; return nil }
    var widget: WidgetSpec? { if case .widget(let w) = content { return w }; return nil }
}

struct AppOverride: Codable, Hashable {
    var name: String?
    var customIconFile: String?
    var art: IconArt?
}

/// Where an item lands on a page grid.
struct Placement: Equatable {
    var index: Int
    var column: Int
    var row: Int
    var columns: Int
    var rows: Int
    var overflow: Bool
}

/// The whole home screen: pages of items, the dock, per-app overrides and user-defined external apps.
/// All mutations are pure value operations so they can be unit-tested and undone.
struct HomeLayout: Codable, Equatable {
    static let columns = 4
    static let rows = 5
    static let dockCapacity = 4

    var version = 1
    var pages: [[HomeItem]]
    var dock: [AppID]
    var overrides: [String: AppOverride] = [:]
    var customApps: [ExternalApp] = []

    // MARK: Grid packing

    /// First-fit packing in reading order. Items that don't fit are flagged `overflow`.
    static func placements(for items: [HomeItem], columns: Int = columns, rows: Int = rows) -> [Placement] {
        var occupied = Array(repeating: Array(repeating: false, count: columns), count: rows)
        var result: [Placement] = []
        for (index, item) in items.enumerated() {
            let span = item.span
            var placed: Placement?
            search: for row in 0..<rows {
                for col in 0..<columns {
                    guard col + span.columns <= columns, row + span.rows <= rows else { continue }
                    var free = true
                    for r in row..<(row + span.rows) {
                        for c in col..<(col + span.columns) where occupied[r][c] { free = false }
                    }
                    if free {
                        for r in row..<(row + span.rows) { for c in col..<(col + span.columns) { occupied[r][c] = true } }
                        placed = Placement(index: index, column: col, row: row, columns: span.columns, rows: span.rows, overflow: false)
                        break search
                    }
                }
            }
            result.append(placed ?? Placement(index: index, column: 0, row: rows, columns: span.columns, rows: span.rows, overflow: true))
        }
        return result
    }

    /// Pushes overflowing items onto following pages and drops empty trailing pages.
    mutating func normalize() {
        var p = 0
        while p < pages.count {
            let placements = Self.placements(for: pages[p])
            let overflowIdx = placements.filter(\.overflow).map(\.index)
            if !overflowIdx.isEmpty {
                let moved = overflowIdx.map { pages[p][$0] }
                for i in overflowIdx.reversed() { pages[p].remove(at: i) }
                if p + 1 >= pages.count { pages.append([]) }
                pages[p + 1].insert(contentsOf: moved, at: 0)
            }
            p += 1
        }
        pages.removeAll { $0.isEmpty }
        if pages.isEmpty { pages = [[]] }
    }

    // MARK: Lookup

    func locate(_ itemID: UUID) -> (page: Int, index: Int)? {
        for (p, page) in pages.enumerated() {
            if let i = page.firstIndex(where: { $0.id == itemID }) { return (p, i) }
        }
        return nil
    }

    func item(_ itemID: UUID) -> HomeItem? {
        locate(itemID).map { pages[$0.page][$0.index] }
    }

    /// Every app currently reachable from the home screen (pages, folders, dock).
    var placedApps: Set<AppID> {
        var set = Set(dock)
        for page in pages {
            for item in page {
                switch item.content {
                case .app(let id): set.insert(id)
                case .folder(let f): set.formUnion(f.apps)
                case .widget: break
                }
            }
        }
        return set
    }

    var allKnownApps: [AppID] {
        BuiltinApp.allCases.map(\.appID) + AppCatalog.externalApps.map(\.id) + customApps.map(\.id)
    }

    // MARK: Mutations

    mutating func addApp(_ id: AppID) {
        guard !placedApps.contains(id) else { return }
        if pages.isEmpty { pages = [[]] }
        // Append to the last page; normalize spills onto a new page if full.
        pages[pages.count - 1].append(.app(id))
        normalize()
    }

    mutating func addWidget(_ spec: WidgetSpec, page: Int? = nil) {
        if pages.isEmpty { pages = [[]] }
        let target = min(max(page ?? pages.count - 1, 0), pages.count - 1)
        pages[target].append(HomeItem(.widget(spec)))
        normalize()
    }

    @discardableResult
    mutating func remove(_ itemID: UUID) -> HomeItem? {
        guard let loc = locate(itemID) else { return nil }
        let removed = pages[loc.page].remove(at: loc.index)
        normalize()
        return removed
    }

    /// Moves an item to `index` on `page` (index is clamped). Creates the page if it's one past the end.
    mutating func move(_ itemID: UUID, toPage page: Int, index: Int) {
        guard let loc = locate(itemID) else { return }
        let item = pages[loc.page].remove(at: loc.index)
        if page >= pages.count { pages.append([]) }
        let target = max(0, min(page, pages.count - 1))
        let clamped = max(0, min(index, pages[target].count))
        pages[target].insert(item, at: clamped)
        normalize()
    }

    /// Drops app `draggedID` onto `targetID`: creates a folder from two apps, or adds to an existing folder.
    /// Returns the folder item's id on success.
    @discardableResult
    mutating func combine(_ draggedID: UUID, onto targetID: UUID) -> UUID? {
        guard draggedID != targetID,
              let dragged = item(draggedID), let draggedApp = dragged.appID,
              let tLoc = locate(targetID) else { return nil }
        let target = pages[tLoc.page][tLoc.index]
        switch target.content {
        case .app(let targetApp):
            let name = Self.suggestFolderName(for: [targetApp, draggedApp])
            pages[tLoc.page][tLoc.index] = HomeItem(id: target.id, .folder(Folder(name: name, apps: [targetApp, draggedApp])))
        case .folder(var folder):
            folder.apps.append(draggedApp)
            pages[tLoc.page][tLoc.index].content = .folder(folder)
        case .widget:
            return nil
        }
        if let dLoc = locate(draggedID) { pages[dLoc.page].remove(at: dLoc.index) }
        normalize()
        return target.id
    }

    mutating func updateFolder(_ folderID: UUID, _ change: (inout Folder) -> Void) {
        guard let loc = locate(folderID), var folder = pages[loc.page][loc.index].folder else { return }
        change(&folder)
        if folder.apps.isEmpty {
            pages[loc.page].remove(at: loc.index)
        } else {
            pages[loc.page][loc.index].content = .folder(folder)
        }
        normalize()
    }

    /// Takes an app out of a folder and places it right after the folder.
    mutating func extract(_ app: AppID, fromFolder folderID: UUID) {
        guard let loc = locate(folderID), var folder = pages[loc.page][loc.index].folder,
              let i = folder.apps.firstIndex(of: app) else { return }
        folder.apps.remove(at: i)
        let insertAt = loc.index + 1
        pages[loc.page].insert(.app(app), at: insertAt)
        if folder.apps.isEmpty { pages[loc.page].remove(at: loc.index) }
        else { pages[loc.page][loc.index].content = .folder(folder) }
        normalize()
    }

    /// Deletes a folder but keeps its apps on the page where the folder was.
    mutating func dissolveFolder(_ folderID: UUID) {
        guard let loc = locate(folderID), let folder = pages[loc.page][loc.index].folder else { return }
        pages[loc.page].remove(at: loc.index)
        pages[loc.page].insert(contentsOf: folder.apps.map { HomeItem.app($0) }, at: loc.index)
        normalize()
    }

    /// Removes an app from a folder entirely (used for "delete" inside a folder).
    mutating func removeApp(_ app: AppID, fromFolder folderID: UUID) {
        updateFolder(folderID) { $0.apps.removeAll { $0 == app } }
    }

    // MARK: Dock

    mutating func moveToDock(_ itemID: UUID, at index: Int) -> Bool {
        guard dock.count < Self.dockCapacity, let item = item(itemID), let app = item.appID else { return false }
        remove(itemID)
        dock.insert(app, at: max(0, min(index, dock.count)))
        return true
    }

    mutating func moveFromDock(_ app: AppID, toPage page: Int, index: Int) {
        guard let i = dock.firstIndex(of: app) else { return }
        dock.remove(at: i)
        if page >= pages.count { pages.append([]) }
        let target = max(0, min(page, pages.count - 1))
        pages[target].insert(.app(app), at: max(0, min(index, pages[target].count)))
        normalize()
    }

    mutating func reorderDock(from: Int, to: Int) {
        guard dock.indices.contains(from) else { return }
        let app = dock.remove(at: from)
        dock.insert(app, at: max(0, min(to, dock.count)))
    }

    mutating func removeFromDock(_ app: AppID) { dock.removeAll { $0 == app } }

    // MARK: Folder naming (iOS 4 suggested a category name for new folders)

    static func suggestFolderName(for apps: [AppID]) -> String {
        let categories = apps.map(category(of:))
        if let first = categories.first, categories.allSatisfy({ $0 == first }) { return L(first) }
        return L("폴더")
    }

    nonisolated static func category(of app: AppID) -> String {
        switch app.raw {
        case "builtin.phone", "builtin.messages", "builtin.contacts", "ext.kakaotalk", "ext.gmail": "소셜"
        case "ext.instagram": "소셜"
        case "builtin.photos", "builtin.camera", "builtin.music", "ext.youtube", "ext.netflix", "ext.spotify", "builtin.voiceMemos": "엔터테인먼트"
        case "builtin.maps", "ext.navermap", "ext.kakaomap": "내비게이션"
        case "ext.toss": "금융"
        case "ext.coupang": "쇼핑"
        case "builtin.browser", "ext.naver", "ext.chatgpt": "생산성"
        default: "유틸리티"
        }
    }

    // MARK: Defaults

    static var `default`: HomeLayout {
        HomeLayout(
            pages: [
                [
                    .widget(.weather, .wide),
                    .app(BuiltinApp.calendar.appID), .app(BuiltinApp.photos.appID),
                    .app(BuiltinApp.camera.appID), .app(BuiltinApp.clock.appID),
                    .app(BuiltinApp.maps.appID), .app(BuiltinApp.notes.appID),
                    .app(BuiltinApp.calculator.appID), .app(BuiltinApp.weather.appID),
                    .app(BuiltinApp.contacts.appID), .app(BuiltinApp.voiceMemos.appID),
                    .app(BuiltinApp.settings.appID),
                ],
                [
                    .widget(.battery, .small), .widget(.calendar, .small),
                    .widget(.analogClock, .small), .widget(.music, .small),
                ],
            ],
            dock: [BuiltinApp.phone.appID, BuiltinApp.messages.appID, BuiltinApp.browser.appID, BuiltinApp.music.appID]
        )
    }
}
