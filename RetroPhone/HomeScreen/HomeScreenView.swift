import SwiftUI

struct HomeScreenView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.deviceInsets) private var insets
    @State private var drag = HomeDragController()
    @State private var pageDrag: CGFloat = 0
    @State private var pressedItem: UUID?
    @State private var suppressNextTap = false
    /// Resets automatically when an item gesture ends *or is cancelled* — used to finish stuck drags.
    @GestureState private var itemGestureActive = false
    @State private var editingApp: AppID?
    @State private var editingWidget: UUID?
    @State private var showAddSheet = false
    @State private var launchError: ExternalApp?

    private var store: LayoutStore { LayoutStore.shared }

    var body: some View {
        GeometryReader { geo in
            let m = HomeMetrics(size: geo.size, insets: insets)
            let layout = store.layout
            let pageCount = layout.pages.count + (drag.isActive ? 1 : 0)

            ZStack(alignment: .topLeading) {
                // Pages
                HStack(spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { p in
                        page(p, metrics: m)
                            .frame(width: m.size.width, height: m.size.height)
                    }
                }
                .offset(x: -CGFloat(router.currentPage) * m.size.width + pageDrag)
                .frame(width: m.size.width, height: m.size.height, alignment: .leading)
                .contentShape(Rectangle())
                // While an icon is being dragged only the icon's gesture may run (no page swipe stealing it).
                .gesture(pagerGesture(m, pageCount: pageCount), including: drag.isActive ? .subviews : .all)

                // Page dots + edit controls
                pageDots(count: pageCount, metrics: m)

                // Dock
                dock(metrics: m)

                // Floating dragged item
                if let item = drag.item {
                    draggedView(item, metrics: m)
                        .position(drag.location)
                        .allowsHitTesting(false)
                        .zIndex(50)
                }

                if let folderID = router.openFolderID, let folderItem = layout.pages.flatMap({ $0 }).first(where: { $0.id == folderID }),
                   folderItem.folder != nil {
                    FolderOverlay(folderItemID: folderID, metrics: m, onLaunch: launch(_:from:), onEditApp: { editingApp = $0 })
                        .zIndex(60)
                        .transition(.opacity)
                }
            }
            .coordinateSpace(name: "home")
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showAddSheet) { AddToHomeSheet().retroModalChrome() }
        .fullScreenCover(item: Binding(get: { editingApp.map(IdentifiedApp.init) }, set: { editingApp = $0?.id })) { app in
            IconEditSheet(app: app.id).retroModalChrome()
        }
        .fullScreenCover(item: Binding(get: { editingWidget.map(IdentifiedUUID.init) }, set: { editingWidget = $0?.id })) { w in
            WidgetEditSheet(itemID: w.id).retroModalChrome()
        }
        .retroAlert(unconfiguredApp.map { LF("%@ 실행 주소가 없습니다", store.name(for: $0)) } ?? "",
                    isPresented: Binding(get: { unconfiguredApp != nil }, set: { if !$0 { unconfiguredApp = nil } }),
                    message: L("스크린샷에서 가져온 앱입니다. iOS는 다른 앱의 실행 주소를 알려 주지 않으니 아이콘 편집에서 주소(예: myapp:// 또는 웹 주소)를 입력하세요."),
                    buttons: [RetroAlertButton(title: L("닫기")), RetroAlertButton(title: L("주소 설정"), isPreferred: true) {
                        let app = unconfiguredApp
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editingApp = app }
                    }])
        .retroAlert(launchError.map { LF("%@ 앱을 열 수 없습니다", $0.displayName) } ?? "",
                    isPresented: Binding(get: { launchError != nil }, set: { if !$0 { launchError = nil } }),
                    message: L("앱이 설치되어 있지 않거나 실행 링크를 지원하지 않습니다."),
                    buttons: launchErrorButtons)
        .task(id: router.screen) {
            // One-time offer to mirror the user's real home screen (not during UI tests).
            guard router.screen == .home, !SettingsStore.shared.value.homeImportOffered, !LaunchOptions.isUITest else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard router.screen == .home else { return }
            SettingsStore.shared.value.homeImportOffered = true
            offerImport = true
        }
        .retroAlert(L("지금 쓰는 아이폰처럼 만들까요?"), isPresented: $offerImport,
                    message: L("실제 홈 화면 스크린샷을 고르면 위젯·폴더·앱 배치를 그대로 옮겨 2010년 스타일로 바꿔 드립니다. 나중에 설정 › 홈 화면에서도 할 수 있습니다."),
                    buttons: [RetroAlertButton(title: L("나중에")), RetroAlertButton(title: L("가져오기"), isPreferred: true) {
                        showImport = true
                    }])
        .fullScreenCover(isPresented: $showImport) { HomeImportView() }
        .onChange(of: itemGestureActive) { _, active in
            // A cancelled gesture never calls onEnded; finish the drag where the finger last was.
            if !active, drag.isActive, let m = drag.metrics { drop(metrics: m) }
        }
        .onChange(of: store.layout.pages.count) { _, count in
            if router.currentPage >= count && !drag.isActive { router.currentPage = max(0, count - 1) }
        }
    }

    // MARK: Page

    @ViewBuilder
    private func page(_ p: Int, metrics m: HomeMetrics) -> some View {
        let items = displayItems(page: p)
        let placements = HomeLayout.placements(for: items)
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(zip(items, placements)), id: \.0.id) { item, placement in
                // Overflowing / dragged items stay in the hierarchy (hidden) so the view that owns an
                // in-flight drag gesture is never destroyed — otherwise the gesture would be cancelled.
                let hidden = placement.overflow || item.id == drag.draggedPageID
                itemView(item, placement: placement, metrics: m, page: p)
                    .opacity(hidden ? 0 : 1)
                    .allowsHitTesting(!placement.overflow || item.id == drag.draggedPageID)
                    .position(placement.overflow ? CGPoint(x: m.size.width / 2, y: m.size.height / 2) : m.center(of: placement))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: items.map(\.id))
    }

    /// Page items rearranged for the live drag preview. The dragged item keeps its identity:
    /// on its source page it moves to the drop target (or to the end when targeting elsewhere);
    /// on other pages a ghost placeholder opens the gap.
    private func displayItems(page p: Int) -> [HomeItem] {
        var items = p < store.layout.pages.count ? store.layout.pages[p] : []
        guard drag.isActive, let dragged = drag.item else { return items }
        let targeting = p == router.currentPage && drag.folderTarget == nil && !drag.overDock
        if let id = drag.draggedPageID, let i = items.firstIndex(where: { $0.id == id }) {
            let item = items.remove(at: i)
            if targeting, let t = drag.targetIndex { items.insert(item, at: min(t, items.count)) }
            else { items.append(item) }
        } else if targeting, let t = drag.targetIndex {
            items.insert(HomeItem(id: Self.ghostID, dragged.content), at: min(t, items.count))
        }
        return items
    }

    static let ghostID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!

    @ViewBuilder
    private func itemView(_ item: HomeItem, placement: Placement, metrics m: HomeMetrics, page: Int) -> some View {
        if item.id == Self.ghostID {
            Color.clear.frame(width: m.frameSize(of: placement).width, height: m.frameSize(of: placement).height)
        } else {
            let editing = router.isEditingHome
            Group {
                switch item.content {
                case .app(let app):
                    AppIconCell(app: app, metrics: m, editing: editing, pressed: pressedItem == item.id,
                                onDelete: app == BuiltinApp.settings.appID ? nil : { delete(item) })
                case .folder(let folder):
                    FolderIconCell(folder: folder, metrics: m, editing: editing, highlighted: drag.folderTarget == item.id,
                                   onDelete: { delete(item) })
                case .widget(let spec):
                    WidgetCell(spec: spec, size: m.widgetSize(spec.size), editing: editing, onDelete: { delete(item) })
                }
            }
            .overlay {
                if drag.folderTarget == item.id, item.appID != nil {
                    // Folder forming behind the target icon.
                    FolderTile(apps: [], size: m.iconSize * 1.25)
                        .offset(y: -m.rowHeight * 0.08)
                        .allowsHitTesting(false)
                        .zIndex(-1)
                }
            }
            .frame(width: m.frameSize(of: placement).width, height: m.frameSize(of: placement).height)
            .contentShape(Rectangle())
            .onTapGesture { tap(item, metrics: m) }
            .simultaneousGesture(itemGesture(source: .page(item.id), item: item, metrics: m))
        }
    }

    // MARK: Dock

    @ViewBuilder
    private func dock(metrics m: HomeMetrics) -> some View {
        let apps = dockDisplayApps(m)
        let centers = m.dockSlotCenters(count: apps.count)
        ZStack(alignment: .topLeading) {
            // With the classic chin the shelf only needs to reach just under it (so it doesn't show
            // as a band when the screen slides up for multitasking).
            let shelfBottom = m.insets.bottom > 60 ? m.size.height - m.insets.bottom + 12 : m.size.height
            DockShelf()
                .frame(width: m.size.width, height: shelfBottom - m.dockTop - m.iconSize * 0.62 + 10)
                .offset(y: m.dockTop + m.iconSize * 0.62)
            ForEach(Array(apps.enumerated()), id: \.element) { i, app in
                if app.raw == "ghost" {
                    Color.clear.frame(width: 1, height: 1).position(centers[i])
                } else {
                    VStack(spacing: 2) {
                        AppIconCell(app: app, metrics: m, editing: router.isEditingHome, showLabel: false,
                                    pressed: pressedDock == app,
                                    onDelete: app == BuiltinApp.settings.appID ? nil : {
                                        store.update { $0.removeFromDock(app) }
                                    })
                        DockReflection(app: app, size: m.iconSize)
                            .frame(height: m.iconSize * 0.3, alignment: .top)
                            .clipped()
                            .opacity(router.isEditingHome ? 0 : 1)
                    }
                    .overlay(alignment: .bottom) {
                        IconLabel(text: store.name(for: app), size: m.labelSize, width: m.cellWidth - 4)
                            .offset(y: -m.iconSize * 0.3 + 18)
                    }
                    .frame(width: m.cellWidth, height: m.iconSize * 1.3 + 4)
                    .contentShape(Rectangle())
                    .onTapGesture { tapDock(app, center: centers[i], metrics: m) }
                    .simultaneousGesture(itemGesture(source: .dock(app), item: .app(app), metrics: m))
                    .opacity(drag.draggedDockApp == app ? 0 : 1)
                    .position(x: centers[i].x, y: centers[i].y + m.iconSize * 0.15)
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: apps)
    }

    @State private var pressedDock: AppID?

    private func dockDisplayApps(_ m: HomeMetrics) -> [AppID] {
        var apps = store.layout.dock
        if let a = drag.draggedDockApp, let from = apps.firstIndex(of: a) {
            // Keep the dragged dock icon alive (hidden) so its gesture isn't cancelled.
            if let i = drag.dockIndex { apps.remove(at: from); apps.insert(a, at: min(i, apps.count)) }
        } else if let i = drag.dockIndex {
            apps.insert(AppID("ghost"), at: min(i, apps.count))
        }
        return apps
    }

    // MARK: Page dots & edit controls

    private func pageDots(count: Int, metrics m: HomeMetrics) -> some View {
        ZStack {
            HStack(spacing: 9) {
                ForEach(0..<count, id: \.self) { i in
                    Circle().fill(Color.white.opacity(i == router.currentPage ? 1 : 0.38)).frame(width: 7, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(LF("페이지 %d/%d", router.currentPage + 1, count))
            if router.isEditingHome {
                HStack {
                    smallGlassButton(systemImage: "plus", label: L("추가")) { showAddSheet = true }
                        .accessibilityIdentifier("homeAddButton")
                    Spacer()
                    smallGlassButton(title: L("완료"), label: L("완료")) {
                        withAnimation(.easeOut(duration: 0.2)) { router.isEditingHome = false }
                    }
                    .accessibilityIdentifier("homeDoneButton")
                }
                .padding(.horizontal, 12)
                .transition(.opacity)
            }
        }
        .frame(width: m.size.width, height: m.dotsHeight)
        .offset(y: m.dockTop - m.dotsHeight - 2)
    }

    private func smallGlassButton(title: String? = nil, systemImage: String? = nil, label: String, action: @escaping () -> Void) -> some View {
        Button {
            SoundService.shared.play(.tock)
            action()
        } label: {
            Group {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 13, weight: .heavy)) }
                if let title { Text(title).font(.retroFixed(13, .bold)) }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 0, y: -1)
            .padding(.horizontal, 10)
            .frame(minWidth: 34, minHeight: 26)
            .background(Capsule().fill(LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().stroke(Color.white.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(label)
    }

    // MARK: Gestures

    private func pagerGesture(_ m: HomeMetrics, pageCount: Int) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                guard !drag.isActive, router.openFolderID == nil else { return }
                var dx = v.translation.width
                // Rubber-band at the ends.
                if (router.currentPage == 0 && dx > 0) || (router.currentPage == pageCount - 1 && dx < 0) { dx /= 3 }
                pageDrag = dx
            }
            .onEnded { v in
                guard !drag.isActive else { return }
                let threshold = m.size.width * 0.25
                let predicted = v.predictedEndTranslation.width
                var page = router.currentPage
                if (v.translation.width < -threshold || predicted < -m.size.width * 0.5), page < pageCount - 1 { page += 1 }
                else if (v.translation.width > threshold || predicted > m.size.width * 0.5), page > 0 { page -= 1 }
                if page != router.currentPage { SoundService.shared.play(.tock) }
                withAnimation(RetroMotion.page) {
                    router.currentPage = page
                    pageDrag = 0
                }
            }
    }

    /// Not editing: touch-and-hold (0.55 s) enters edit mode and can continue straight into a drag.
    /// Editing: any movement ≥ 6 pt drags the icon (like iOS 4); a still press stays a tap.
    private func itemGesture(source: HomeDragController.Source, item: HomeItem, metrics m: HomeMetrics) -> AnyGesture<Void> {
        if router.isEditingHome {
            return AnyGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named("home"))
                    .updating($itemGestureActive) { _, state, _ in state = true }
                    .onChanged { d in dragChanged(d, source: source, item: item, metrics: m) }
                    .onEnded { _ in if drag.isActive { drop(metrics: m) } }
                    .map { _ in () }
            )
        }
        return AnyGesture(
            LongPressGesture(minimumDuration: 0.55, maximumDistance: 10)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("home")))
                .updating($itemGestureActive) { _, state, _ in state = true }
                .onChanged { value in
                    // `.first(true)` only means the finger is down; the hold completed once we reach `.second`.
                    guard case .second(true, let d) = value else { return }
                    if !suppressNextTap {
                        suppressNextTap = true   // the finger lift after a hold must not count as a tap
                        // Safety net: entering edit mode swaps this gesture out, so onEnded may never run.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { suppressNextTap = false }
                    }
                    enterEditing()
                    if let d { dragChanged(d, source: source, item: item, metrics: m) }
                }
                .onEnded { _ in
                    if drag.isActive { drop(metrics: m) }
                    clearSuppressSoon()
                }
                .map { _ in () }
        )
    }

    private func clearSuppressSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { suppressNextTap = false }
    }

    private func dragChanged(_ d: DragGesture.Value, source: HomeDragController.Source, item: HomeItem, metrics m: HomeMetrics) {
        if !drag.isActive {
            var origin: Int?
            if case .page(let id) = source { origin = store.layout.locate(id)?.index }
            drag.begin(source, item: item, at: d.location, originIndex: origin)
        }
        let pageItems = router.currentPage < store.layout.pages.count ? store.layout.pages[router.currentPage] : []
        drag.update(to: d.location, metrics: m, pageItems: pageItems, dockCount: store.layout.dock.count) { dir in
            flipPage(dir)
        }
    }

    private func enterEditing() {
        guard !router.isEditingHome else { return }
        Haptics.tap(.heavy)
        withAnimation(.easeOut(duration: 0.2)) { router.isEditingHome = true }
    }

    private func flipPage(_ dir: Int) {
        let maxPage = store.layout.pages.count // one past the end allowed while dragging
        let next = router.currentPage + dir
        guard next >= 0, next <= maxPage else { return }
        SoundService.shared.play(.tock)
        withAnimation(RetroMotion.page) {
            router.currentPage = next
            drag.targetIndex = nil
        }
    }

    // MARK: Drop

    private func drop(metrics m: HomeMetrics) {
        guard let source = drag.source, let item = drag.item else { drag.reset(); return }
        let page = router.currentPage
        let inDock = m.isInDock(drag.location)
        let dockIndex = drag.dockIndex
        let folderTarget = drag.folderTarget
        let targetIndex = drag.targetIndex

        withAnimation(.easeInOut(duration: 0.22)) {
            store.update { l in
                if inDock {
                    switch source {
                    case .dock(let app):
                        if let from = l.dock.firstIndex(of: app) { l.reorderDock(from: from, to: dockIndex ?? from) }
                    case .page(let id):
                        if item.appID != nil, let dockIndex { _ = l.moveToDock(id, at: dockIndex) }
                    }
                    return
                }
                if let folderTarget, let app = item.appID {
                    var draggedID: UUID?
                    switch source {
                    case .page(let id): draggedID = id
                    case .dock(let a):
                        l.moveFromDock(a, toPage: page, index: Int.max)
                        draggedID = l.pages.flatMap { $0 }.last { $0.appID == app }?.id
                    }
                    if let draggedID { l.combine(draggedID, onto: folderTarget) }
                    return
                }
                let pageCount = l.pages.count
                let index = targetIndex ?? (page < pageCount ? l.pages[page].count : 0)
                switch source {
                case .page(let id): l.move(id, toPage: page, index: index)
                case .dock(let app): l.moveFromDock(app, toPage: page, index: index)
                }
            }
            drag.reset()
        }
        SoundService.shared.play(.tock)
        if router.currentPage >= store.layout.pages.count { router.currentPage = store.layout.pages.count - 1 }
    }

    // MARK: Taps

    private func tap(_ item: HomeItem, metrics m: HomeMetrics) {
        if suppressNextTap { suppressNextTap = false; return }
        guard !drag.isActive else { return }
        let center = store.layout.locate(item.id).map { loc -> CGPoint in
            let placements = HomeLayout.placements(for: store.layout.pages[loc.page])
            return m.center(of: placements[loc.index])
        } ?? CGPoint(x: m.size.width / 2, y: m.size.height / 2)
        let anchor = UnitPoint(x: center.x / m.size.width, y: center.y / m.size.height)

        switch item.content {
        case .app(let app):
            if router.isEditingHome { editingApp = app; return }
            flash(item.id)
            launch(app, from: anchor)
        case .folder:
            SoundService.shared.play(.folderOpen)
            withAnimation(RetroMotion.folder) { router.openFolderID = item.id }
        case .widget(let spec):
            if router.isEditingHome { editingWidget = item.id; return }
            if let app = spec.kind.linkedApp { router.open(app, anchor: anchor) }
        }
    }

    private func tapDock(_ app: AppID, center: CGPoint, metrics m: HomeMetrics) {
        if suppressNextTap { suppressNextTap = false; return }
        guard !drag.isActive else { return }
        if router.isEditingHome { editingApp = app; return }
        pressedDock = app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { pressedDock = nil }
        launch(app, from: UnitPoint(x: center.x / m.size.width, y: center.y / m.size.height))
    }

    private func flash(_ id: UUID) {
        pressedItem = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { pressedItem = nil }
    }

    func launch(_ app: AppID, from anchor: UnitPoint) {
        if let builtin = app.builtin {
            if store.layout.overrides[app.raw]?.openSystemApp == true {
                Task {
                    // Fall back to the classic app if iOS can't open the system one.
                    if !(await ExternalAppLauncher.openSystemVersion(of: builtin)) { router.open(builtin, anchor: anchor) }
                }
            } else {
                router.open(builtin, anchor: anchor)
            }
        } else if let ext = store.external(app) {
            if ext.scheme == nil && ext.webURL == nil { unconfiguredApp = app; return }
            Task {
                let ok = await ExternalAppLauncher.open(ext)
                if !ok { launchError = ext }
            }
        }
    }

    @State private var unconfiguredApp: AppID?
    @State private var offerImport = false
    @State private var showImport = false

    private var launchErrorButtons: [RetroAlertButton] {
        guard let ext = launchError else { return [] }
        var buttons = [RetroAlertButton(title: L("닫기"))]
        if ext.appStoreID != nil {
            buttons.append(RetroAlertButton(title: L("App Store"), isPreferred: true) {
                ExternalAppLauncher.openAppStore(ext)
            })
        }
        return buttons
    }

    private func delete(_ item: HomeItem) {
        Haptics.tap()
        withAnimation(.easeInOut(duration: 0.25)) {
            store.update { l in
                if item.folder != nil { l.dissolveFolder(item.id) } else { l.remove(item.id) }
            }
        }
    }

    // MARK: Dragged view

    @ViewBuilder
    private func draggedView(_ item: HomeItem, metrics m: HomeMetrics) -> some View {
        Group {
            switch item.content {
            case .app(let app): AppIconCell(app: app, metrics: m, editing: false)
            case .folder(let f): FolderIconCell(folder: f, metrics: m, editing: false)
            case .widget(let spec): WidgetCell(spec: spec, size: m.widgetSize(spec.size), editing: false)
            }
        }
        .scaleEffect(1.2)
        .opacity(0.85)
        .shadow(color: .black.opacity(0.5), radius: 8, y: 6)
    }
}

struct IdentifiedApp: Identifiable { var id: AppID }
struct IdentifiedUUID: Identifiable { var id: UUID }
