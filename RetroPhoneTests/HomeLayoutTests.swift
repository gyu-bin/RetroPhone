import XCTest
@testable import RetroPhone

final class HomeLayoutTests: XCTestCase {
    private func app(_ name: String) -> HomeItem { .app(AppID("builtin.\(name)")) }

    func testPackingPlacesWideWidgetThenAppsInReadingOrder() {
        let items: [HomeItem] = [.widget(.weather, .wide), app("phone"), app("notes"), app("maps"), app("clock"), app("camera")]
        let p = HomeLayout.placements(for: items)
        XCTAssertEqual(p[0].column, 0); XCTAssertEqual(p[0].row, 0); XCTAssertEqual(p[0].columns, 4); XCTAssertEqual(p[0].rows, 2)
        XCTAssertEqual(p[1].row, 2); XCTAssertEqual(p[1].column, 0)
        XCTAssertEqual(p[4].row, 2); XCTAssertEqual(p[4].column, 3)
        XCTAssertEqual(p[5].row, 3); XCTAssertEqual(p[5].column, 0)
        XCTAssertTrue(p.allSatisfy { !$0.overflow })
    }

    func testSmallWidgetsFillGapsFirstFit() {
        // An app first, then a 2x2: the widget can't start at column 1 row 0? It can (cols 1-2).
        let items: [HomeItem] = [app("phone"), .widget(.battery, .small), app("notes")]
        let p = HomeLayout.placements(for: items)
        XCTAssertEqual(p[1].column, 1); XCTAssertEqual(p[1].row, 0)
        XCTAssertEqual(p[2].column, 3); XCTAssertEqual(p[2].row, 0)
    }

    func testOverflowFlagsItemsBeyondGrid() {
        let items = (0..<(HomeLayout.columns * HomeLayout.rows + 2)).map { _ in app("phone") }
        let p = HomeLayout.placements(for: items)
        XCTAssertEqual(p.filter(\.overflow).count, 2)
    }

    func testNormalizeSpillsOverflowToNextPage() {
        let capacity = HomeLayout.columns * HomeLayout.rows
        var l = HomeLayout(pages: [(0..<(capacity + 2)).map { _ in app("phone") }], dock: [])
        l.normalize()
        XCTAssertEqual(l.pages.count, 2)
        guard l.pages.count == 2 else { return }
        XCTAssertEqual(l.pages[0].count, capacity)
        XCTAssertEqual(l.pages[1].count, 2)
    }

    func testNormalizeDropsEmptyPagesButKeepsOne() {
        var l = HomeLayout(pages: [[], [app("phone")], []], dock: [])
        l.normalize()
        XCTAssertEqual(l.pages.count, 1)
        var empty = HomeLayout(pages: [[], []], dock: [])
        empty.normalize()
        XCTAssertEqual(empty.pages.count, 1)
    }

    func testMoveWithinAndAcrossPages() {
        let a = app("phone"), b = app("notes"), c = app("maps")
        var l = HomeLayout(pages: [[a, b, c], []], dock: [])
        l.move(c.id, toPage: 0, index: 0)
        XCTAssertEqual(l.pages[0].map(\.id), [c.id, a.id, b.id])
        l.move(a.id, toPage: 1, index: 0)
        XCTAssertEqual(l.pages.count, 2)
        XCTAssertEqual(l.pages[1].map(\.id), [a.id])
    }

    func testCombineTwoAppsCreatesFolderWithCategoryName() {
        Localizer.shared.language = .ko
        let maps = HomeItem.app("builtin.maps"), nmap = HomeItem.app("ext.navermap")
        var l = HomeLayout(pages: [[maps, nmap]], dock: [])
        let folderID = l.combine(nmap.id, onto: maps.id)
        XCTAssertEqual(folderID, maps.id)
        XCTAssertEqual(l.pages[0].count, 1)
        let folder = l.pages[0][0].folder
        XCTAssertEqual(folder?.apps, ["builtin.maps", "ext.navermap"])
        XCTAssertEqual(folder?.name, "내비게이션")
    }

    func testCombineIntoExistingFolderAndExtract() {
        let f = HomeItem(.folder(Folder(name: "X", apps: ["builtin.maps"])))
        let notes = app("notes")
        var l = HomeLayout(pages: [[f, notes]], dock: [])
        l.combine(notes.id, onto: f.id)
        XCTAssertEqual(l.pages[0].count, 1)
        XCTAssertEqual(l.pages[0][0].folder?.apps, ["builtin.maps", "builtin.notes"])
        l.extract("builtin.maps", fromFolder: f.id)
        XCTAssertEqual(l.pages[0].count, 2)
        XCTAssertEqual(l.pages[0][1].appID, "builtin.maps")
        // Removing the last app deletes the folder.
        l.removeApp("builtin.notes", fromFolder: f.id)
        XCTAssertNil(l.item(f.id))
    }

    func testWidgetsCannotBeFolderTargets() {
        let w = HomeItem.widget(.battery, .small), a = app("phone")
        var l = HomeLayout(pages: [[w, a]], dock: [])
        XCTAssertNil(l.combine(a.id, onto: w.id))
        XCTAssertEqual(l.pages[0].count, 2)
    }

    func testDissolveFolderKeepsApps() {
        let f = HomeItem(.folder(Folder(name: "X", apps: ["builtin.maps", "builtin.notes"])))
        var l = HomeLayout(pages: [[app("phone"), f]], dock: [])
        l.dissolveFolder(f.id)
        XCTAssertEqual(l.pages[0].compactMap(\.appID), ["builtin.phone", "builtin.maps", "builtin.notes"])
    }

    func testDockCapacityAndMoves() {
        let a = app("notes")
        var l = HomeLayout(pages: [[a]], dock: ["builtin.phone", "builtin.messages", "builtin.browser", "builtin.music"])
        XCTAssertFalse(l.moveToDock(a.id, at: 0), "dock is full")
        l.removeFromDock("builtin.music")
        XCTAssertTrue(l.moveToDock(a.id, at: 1))
        XCTAssertEqual(l.dock[1], "builtin.notes")
        l.moveFromDock("builtin.phone", toPage: 0, index: 0)
        XCTAssertEqual(l.pages[0].first?.appID, "builtin.phone")
        l.reorderDock(from: 0, to: 2)
        XCTAssertEqual(l.dock, ["builtin.messages", "builtin.browser", "builtin.notes"])
    }

    func testPlacedAppsIncludesFoldersAndDockAndAddAppIsIdempotent() {
        var l = HomeLayout.default
        XCTAssertTrue(BuiltinApp.allCases.allSatisfy { l.placedApps.contains($0.appID) })
        let before = l.pages.flatMap { $0 }.count
        l.addApp("builtin.phone")
        XCTAssertEqual(l.pages.flatMap { $0 }.count, before)
        l.addApp("ext.kakaotalk")
        XCTAssertTrue(l.placedApps.contains("ext.kakaotalk"))
    }

    func testCodableRoundTrip() throws {
        var l = HomeLayout.default
        l.overrides["builtin.notes"] = AppOverride(name: "📒 노트", customIconFile: nil, art: .book)
        l.customApps.append(ExternalApp(id: "custom.1", nameKo: "앱", nameEn: "App", scheme: "myapp://", webURL: nil,
                                        appStoreID: nil, verification: .community, art: .star))
        l.pages[0].append(HomeItem(.folder(Folder(name: "🎮 게임", apps: ["custom.1"]))))
        let data = try JSONEncoder().encode(l)
        let decoded = try JSONDecoder().decode(HomeLayout.self, from: data)
        XCTAssertEqual(decoded, l)
    }

    func testInsertionIndex() {
        let items: [HomeItem] = [.widget(.weather, .wide), app("a"), app("b")]
        let p = HomeLayout.placements(for: items)
        // Inside the widget → before it.
        XCTAssertEqual(HomeMetrics.insertionIndex(for: (column: 2, row: 1), placements: p), 0)
        // Row 2, column 1 → before "b".
        XCTAssertEqual(HomeMetrics.insertionIndex(for: (column: 1, row: 2), placements: p), 2)
        // Empty area → end.
        XCTAssertEqual(HomeMetrics.insertionIndex(for: (column: 0, row: 4), placements: p), 3)
    }
}
