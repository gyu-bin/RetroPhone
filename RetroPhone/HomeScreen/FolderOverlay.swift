import SwiftUI

/// iOS 4-style folder: the home screen dims and a linen panel opens with the folder's apps.
/// In edit mode: rename, drag to reorder, drag out of the panel to move an app back to the page.
struct FolderOverlay: View {
    @Environment(AppRouter.self) private var router
    var folderItemID: UUID
    var metrics: HomeMetrics
    var onLaunch: (AppID, UnitPoint) -> Void
    var onEditApp: (AppID) -> Void

    @State private var name = ""
    @State private var dragApp: AppID?
    @State private var dragLocation: CGPoint = .zero
    @State private var targetIndex: Int?
    @State private var shown = false
    @State private var suppressNextTap = false
    @FocusState private var nameFocused: Bool

    private var store: LayoutStore { LayoutStore.shared }
    private var folder: Folder? { store.layout.item(folderItemID)?.folder }

    var body: some View {
        let m = metrics
        let apps = displayApps
        let rows = max(1, Int(ceil(Double(apps.count) / 4)))
        let gridHeight = CGFloat(rows) * m.rowHeight
        let panelHeight = gridHeight + 70
        let panelTop = max(m.gridTop + m.rowHeight * 0.9, (m.size.height - panelHeight) / 2 - 40)

        ZStack(alignment: .topLeading) {
            Color.black.opacity(shown ? 0.55 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                Group {
                    if router.isEditingHome {
                        TextField(L("폴더 이름"), text: $name)
                            .focused($nameFocused)
                            .font(.retroFixed(20, .bold))
                            .foregroundStyle(Color(hex: 0x1A1A1A))
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.92)))
                            .submitLabel(.done)
                            .onSubmit(commitName)
                            .accessibilityIdentifier("folderNameField")
                    } else {
                        Text(folder?.name ?? "")
                            .font(.retroFixed(20, .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.8), radius: 0, y: -1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                ZStack(alignment: .topLeading) {
                    Color.clear
                    ForEach(Array(apps.enumerated()), id: \.element) { i, app in
                        let center = CGPoint(x: (CGFloat(i % 4) + 0.5) * m.cellWidth, y: (CGFloat(i / 4) + 0.5) * m.rowHeight)
                        if app.raw == "ghost" {
                            Color.clear.frame(width: 1, height: 1).position(center)
                        } else {
                            AppIconCell(app: app, metrics: m, editing: router.isEditingHome,
                                        onDelete: { extract(app) })
                                .frame(width: m.cellWidth, height: m.rowHeight)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if suppressNextTap { suppressNextTap = false; return }
                                    if router.isEditingHome { onEditApp(app); return }
                                    let y = panelTop + 58 + center.y
                                    close(animated: false)
                                    onLaunch(app, UnitPoint(x: center.x / m.size.width, y: y / m.size.height))
                                }
                                .simultaneousGesture(reorderGesture(app, panelTop: panelTop, panelHeight: panelHeight))
                                .opacity(dragApp == app ? 0 : 1)
                                .position(center)
                        }
                    }
                }
                .frame(height: gridHeight)
                .animation(.easeInOut(duration: 0.2), value: apps)
                .padding(.bottom, 10)
            }
            .frame(width: m.size.width)
            .background(
                ZStack {
                    WallpaperView(choice: .builtin(.linen))
                    VStack {
                        LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom).frame(height: 10)
                        Spacer()
                        LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom).frame(height: 10)
                    }
                }
            )
            .clipped()
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1) }
            .scaleEffect(y: shown ? 1 : 0.01, anchor: .top)
            .offset(y: panelTop)

            if let dragApp {
                AppIconCell(app: dragApp, metrics: m, editing: false)
                    .scaleEffect(1.2).opacity(0.85)
                    .position(dragLocation)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "folder")
        .onAppear {
            name = folder?.name ?? ""
            withAnimation(RetroMotion.folder) { shown = true }
        }
        .onChange(of: router.isEditingHome) { _, editing in if !editing { commitName() } }
        .onDisappear(perform: commitName)
    }

    private var displayApps: [AppID] {
        var apps = folder?.apps ?? []
        // The dragged icon keeps its view identity (hidden) so its gesture isn't cancelled.
        if let dragApp, let targetIndex, let from = apps.firstIndex(of: dragApp) {
            apps.remove(at: from)
            apps.insert(dragApp, at: min(targetIndex, apps.count))
        }
        return apps
    }

    private func reorderGesture(_ app: AppID, panelTop: CGFloat, panelHeight: CGFloat) -> AnyGesture<Void> {
        if router.isEditingHome {
            return AnyGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named("folder"))
                    .onChanged { d in reorderChanged(d, app: app, panelTop: panelTop, panelHeight: panelHeight) }
                    .onEnded { _ in reorderEnded() }
                    .map { _ in () }
            )
        }
        return AnyGesture(
            LongPressGesture(minimumDuration: 0.55, maximumDistance: 10)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("folder")))
                .onChanged { value in
                    guard case .second(true, let d) = value else { return }
                    if !suppressNextTap {
                        suppressNextTap = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { suppressNextTap = false }
                    }
                    if !router.isEditingHome { Haptics.tap(.heavy); router.isEditingHome = true }
                    if let d { reorderChanged(d, app: app, panelTop: panelTop, panelHeight: panelHeight) }
                }
                .onEnded { _ in
                    reorderEnded()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { suppressNextTap = false }
                }
                .map { _ in () }
        )
    }

    private func reorderChanged(_ d: DragGesture.Value, app: AppID, panelTop: CGFloat, panelHeight: CGFloat) {
        if dragApp == nil { dragApp = app; targetIndex = folder?.apps.firstIndex(of: app); Haptics.tap(.medium) }
        dragLocation = d.location
        let local = CGPoint(x: d.location.x, y: d.location.y - panelTop - 58)
        let inside = d.location.y > panelTop && d.location.y < panelTop + panelHeight
        if inside {
            let col = max(0, min(3, Int(local.x / metrics.cellWidth)))
            let row = max(0, Int(local.y / metrics.rowHeight))
            let count = (folder?.apps.count ?? 1) - 1
            let idx = min(row * 4 + col, count)
            if idx != targetIndex { withAnimation(.easeInOut(duration: 0.2)) { targetIndex = idx } }
        } else {
            targetIndex = nil
        }
    }

    private func reorderEnded() {
        guard let dragApp else { return }
        if let targetIndex {
            store.update { l in
                l.updateFolder(folderItemID) { f in
                    f.apps.removeAll { $0 == dragApp }
                    f.apps.insert(dragApp, at: min(targetIndex, f.apps.count))
                }
            }
        } else {
            extract(dragApp)
        }
        self.dragApp = nil
        self.targetIndex = nil
    }

    private func extract(_ app: AppID) {
        Haptics.tap()
        let remaining = (folder?.apps.count ?? 0) - 1
        withAnimation(.easeInOut(duration: 0.25)) {
            store.update { $0.extract(app, fromFolder: folderItemID) }
        }
        if remaining <= 0 { close() }
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder?.name, folder != nil else { return }
        store.update { $0.updateFolder(folderItemID) { $0.name = trimmed } }
    }

    private func close(animated: Bool = true) {
        commitName()
        nameFocused = false
        SoundService.shared.play(.folderClose)
        if animated {
            withAnimation(RetroMotion.folder) { shown = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { router.openFolderID = nil }
        } else {
            router.openFolderID = nil
        }
    }
}
