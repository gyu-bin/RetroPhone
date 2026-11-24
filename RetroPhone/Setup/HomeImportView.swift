import SwiftUI
import PhotosUI

/// "Make my iPhone look like 2010": rebuilds the RetroPhone home screen from screenshots of the user's
/// real home screen pages. Everything runs on-device (Vision OCR + image crops).
///
/// - Apps RetroPhone knows get a classic icon (or keep their real icon if the user prefers).
/// - Unknown apps keep their real icon (cropped from the screenshot, then glossed like iOS 4) and become
///   shortcuts whose launch address the user can set later.
/// - Dock icons have no labels on iOS 26+, so the user assigns them from the cropped previews.
struct HomeImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    var onFinished: (() -> Void)? = nil

    struct Item: Identifiable {
        let id = UUID()
        var label: String
        var match: AppID?
        var isFolder: Bool
        var crop: UIImage?
        var include = true
    }
    struct Page: Identifiable {
        let id = UUID()
        var items: [Item]
    }
    struct DockSlot: Identifiable {
        let id = UUID()
        var app: AppID?
    }

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pages: [Page] = []
    @State private var dock: [DockSlot] = []
    @State private var dockStrip: UIImage?
    @State private var analyzing = false
    @State private var keepRealIcons = false
    @State private var addInstalled = true
    @State private var keepWidgets = true
    @State private var installed: [ExternalApp] = []
    @State private var failed = false
    @State private var confirmApply = false

    private var store: LayoutStore { LayoutStore.shared }

    var body: some View {
        ClassicPage(title: L("내 홈 화면 가져오기"), leading: {
            ClassicBarButton(title: L("취소")) { dismiss() }
        }, trailing: {
            ClassicBarButton(title: L("적용"), kind: .done) { confirmApply = true }
                .disabled(pages.isEmpty && installed.isEmpty)
                .opacity(pages.isEmpty && installed.isEmpty ? 0.5 : 1)
        }) {
            ScrollView {
                VStack(spacing: 0) {
                    intro
                    if analyzing {
                        ProgressView(L("분석 중…")).padding(30)
                    }
                    ForEach(Array(pages.enumerated()), id: \.element.id) { pageIndex, page in
                        pageSection(pageIndex, page)
                    }
                    if !dock.isEmpty { dockSection }
                    if !pages.isEmpty || !installed.isEmpty { optionsSection }
                    Color.clear.frame(height: 40)
                }
            }
        }
        .retroModalChrome()
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await analyze(items) }
        }
        .task { installed = ExternalAppLauncher.installedCatalogApps() }
        .retroAlert(L("스크린샷을 분석하지 못했습니다"), isPresented: $failed,
                    message: L("앱 이름이 보이는 홈 화면 스크린샷인지 확인하세요. (아이콘만 크게 보기 모드는 이름이 없어 인식할 수 없습니다)"))
        .retroAlert(L("홈 화면을 바꿀까요?"), isPresented: $confirmApply,
                    message: L("지금 RetroPhone 홈 화면 배치가 가져온 배치로 바뀝니다. 설정 › 레이아웃 백업으로 미리 저장해 둘 수 있습니다."),
                    buttons: [RetroAlertButton(title: L("취소")), RetroAlertButton(title: L("적용"), isPreferred: true) { apply() }])
    }

    // MARK: Sections

    private var intro: some View {
        VStack(spacing: 0) {
            Text(L("실제 아이폰 홈 화면을 페이지마다 스크린샷으로 찍은 뒤 순서대로 선택하세요. 앱 이름과 위치를 기기 안에서 읽어 RetroPhone 홈 화면을 똑같이 구성합니다."))
                .font(.retro(14)).foregroundStyle(Color(hex: 0x4C566C)).embossed()
                .multilineTextAlignment(.center).padding(.horizontal, 20).padding(.top, 14)
            GroupedSection {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, selectionBehavior: .ordered, matching: .screenshots) {
                    TableRow(title: pages.isEmpty ? L("홈 화면 스크린샷 선택…") : L("스크린샷 다시 선택…"),
                             systemIcon: "photo.stack", chevron: true)
                }
                .disabled(analyzing)
                .accessibilityIdentifier("importPickScreenshots")
            }
        }
    }

    private func pageSection(_ pageIndex: Int, _ page: Page) -> some View {
        GroupedSection(header: LF("%d페이지", pageIndex + 1),
                       footer: pageIndex == pages.count - 1 ? L("알 수 없는 앱은 실제 아이콘을 그대로 쓰고, 실행 주소는 나중에 아이콘 편집에서 정할 수 있습니다.") : nil) {
            if page.items.isEmpty {
                TableRow(title: L("인식된 앱 없음"))
            }
            ForEach(Array(page.items.enumerated()), id: \.element.id) { itemIndex, item in
                HStack(spacing: 10) {
                    itemIcon(item)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label).font(.retro(16, .bold)).lineLimit(1)
                        Text(subtitle(item)).font(.retro(12)).foregroundStyle(Color(hex: 0x385487)).lineLimit(1)
                    }
                    Spacer()
                    RetroToggle(isOn: Binding(get: { pages[pageIndex].items[itemIndex].include },
                                              set: { pages[pageIndex].items[itemIndex].include = $0 }), label: item.label)
                }
                .padding(.horizontal, 10).frame(minHeight: 52)
            }
        }
    }

    private func subtitle(_ item: Item) -> String {
        if item.isFolder { return L("폴더 · 안의 앱은 직접 옮겨 담으세요") }
        if let id = item.match { return store.name(for: id) + " · " + (id.builtin != nil ? L("클래식 앱") : L("연결됨")) }
        return L("알 수 없는 앱 · 실제 아이콘 유지")
    }

    @ViewBuilder
    private func itemIcon(_ item: Item) -> some View {
        if item.isFolder {
            FolderTile(apps: [], size: 36)
        } else if let id = item.match, !keepRealIcons || item.crop == nil {
            RetroIconView(art: store.art(for: id), size: 36)
        } else {
            RetroIconView(art: .generic, size: 36, customImage: item.crop)
        }
    }

    private var dockSection: some View {
        GroupedSection(header: L("독"), footer: L("iOS 독 아이콘에는 이름이 없어 직접 지정해야 합니다. 위 스크린샷의 독을 보고 왼쪽부터 고르세요.")) {
            if let dockStrip {
                Image(uiImage: dockStrip).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6)).padding(8)
                    .accessibilityLabel(L("스크린샷의 독"))
            }
            ForEach(Array(dock.enumerated()), id: \.element.id) { i, slot in
                HStack(spacing: 10) {
                    Text("\(i + 1)").font(.retro(15, .bold)).foregroundStyle(Color(hex: 0x7A8494)).frame(width: 20)
                    Menu {
                        Button(L("비워 두기")) { dock[i].app = nil }
                        Section(L("클래식 앱")) {
                            ForEach(BuiltinApp.allCases) { b in Button(L(b.nameKo)) { dock[i].app = b.appID } }
                        }
                        Section(L("이 기기에 설치된 앱")) {
                            ForEach(installed) { e in Button(e.displayName) { dock[i].app = e.id } }
                        }
                        Section(L("iOS 기본 앱")) {
                            ForEach(AppCatalog.systemApps) { e in Button(e.displayName) { dock[i].app = e.id } }
                        }
                    } label: {
                        HStack {
                            if let app = slot.app {
                                RetroIconView(art: store.art(for: app), size: 30)
                                Text(store.name(for: app)).font(.retro(16, .bold)).foregroundStyle(.black)
                            } else {
                                Text(L("앱 선택…")).font(.retro(16)).foregroundStyle(Color(hex: 0x385487))
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").foregroundStyle(Color(hex: 0x7F7F7F))
                        }
                    }
                }
                .padding(.horizontal, 10).frame(minHeight: 52)
            }
        }
    }

    private var optionsSection: some View {
        GroupedSection(header: L("옵션"), footer: installed.isEmpty ? nil
                       : LF("이 기기에서 RetroPhone이 알고 있는 앱 %d개를 찾았습니다. (설치 여부는 기기 안에서만 확인)", installed.count)) {
            TableRow(title: L("알려진 앱도 실제 아이콘 사용"), accessory: { RetroToggle(isOn: $keepRealIcons) })
            TableRow(title: L("스크린샷에 없는 설치된 앱 추가"), accessory: { RetroToggle(isOn: $addInstalled) })
            TableRow(title: L("레트로 위젯 페이지 유지"), accessory: { RetroToggle(isOn: $keepWidgets) })
        }
    }

    // MARK: Analysis

    private func analyze(_ items: [PhotosPickerItem]) async {
        analyzing = true
        defer { analyzing = false }
        var newPages: [Page] = []
        var strip: UIImage?
        for (i, pickerItem) in items.enumerated() {
            guard let data = try? await pickerItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)?.normalizedOrientation(),
                  let labels = try? await ScreenshotLayoutImporter.recognizeLabels(in: image) else { continue }
            let size = CGSize(width: image.cgImage?.width ?? 0, height: image.cgImage?.height ?? 0)
            let pageItems = ScreenshotLayoutImporter.appLabels(labels).map { label -> Item in
                let crop = ScreenshotLayoutImporter.crop(image, to: ScreenshotLayoutImporter.iconRect(above: label, imageSize: size))
                let folder = ScreenshotLayoutImporter.isLikelyFolder(label.text)
                return Item(label: label.text, match: folder ? nil : ScreenshotLayoutImporter.match(label.text),
                            isFolder: folder, crop: crop)
            }
            newPages.append(Page(items: pageItems))
            if i == 0 { strip = ScreenshotLayoutImporter.crop(image, to: ScreenshotLayoutImporter.dockStripRect(imageSize: size)) }
        }
        if newPages.allSatisfy({ $0.items.isEmpty }) { failed = true; return }
        // Start from the current RetroPhone dock; the user adjusts it to match the screenshot.
        var slots = (0..<HomeLayout.dockCapacity).map { _ in DockSlot(app: nil) }
        for (i, app) in store.layout.dock.prefix(slots.count).enumerated() { slots[i].app = app }
        pages = newPages
        dock = slots
        dockStrip = strip
        Haptics.success()
    }

    // MARK: Apply

    private func apply() {
        var layout = store.layout
        var customApps = layout.customApps
        var overrides = layout.overrides
        var newPages: [[HomeItem]] = []
        var placed = Set<AppID>()

        let dockApps = dock.compactMap(\.app)
        placed.formUnion(dockApps)

        for page in pages {
            var items: [HomeItem] = []
            for item in page.items where item.include {
                if item.isFolder {
                    items.append(HomeItem(.folder(Folder(name: item.label, apps: []))))
                    continue
                }
                if let id = item.match {
                    guard !placed.contains(id) else { continue }
                    placed.insert(id)
                    items.append(.app(id))
                    if keepRealIcons, let crop = item.crop, let file = FileStore.saveImage(crop, maxDimension: 240) {
                        var o = overrides[id.raw] ?? AppOverride()
                        o.customIconFile = file
                        overrides[id.raw] = o
                    }
                } else {
                    // Unknown app: keep its real icon and name; the user can set a launch address later.
                    let id = AppID("custom.\(UUID().uuidString)")
                    customApps.append(ExternalApp(id: id, nameKo: item.label, nameEn: item.label, scheme: nil, webURL: nil,
                                                  appStoreID: nil, verification: .webOnly, art: .generic))
                    if let crop = item.crop, let file = FileStore.saveImage(crop, maxDimension: 240) {
                        overrides[id.raw] = AppOverride(name: nil, customIconFile: file, art: nil)
                    }
                    placed.insert(id)
                    items.append(.app(id))
                }
            }
            if !items.isEmpty { newPages.append(items) }
        }

        // Installed apps that weren't in the screenshots.
        var extra: [HomeItem] = []
        if addInstalled {
            extra += installed.filter { !placed.contains($0.id) }.map { HomeItem.app($0.id) }
            installed.forEach { placed.insert($0.id) }
        }
        // Keep every classic app reachable (Settings in particular) in a folder.
        let leftovers = BuiltinApp.allCases.map(\.appID).filter { !placed.contains($0) }
        if !leftovers.isEmpty {
            extra.append(HomeItem(.folder(Folder(name: L("클래식 앱"), apps: leftovers))))
        }
        if !extra.isEmpty { newPages.append(extra) }
        if keepWidgets {
            newPages.append([.widget(.weather, .wide), .widget(.calendar, .small), .widget(.battery, .small),
                             .widget(.music, .wide)])
        }

        layout.pages = newPages.isEmpty ? [[]] : newPages
        if !dockApps.isEmpty { layout.dock = Array(dockApps.prefix(HomeLayout.dockCapacity)) }
        layout.customApps = customApps
        layout.overrides = overrides
        layout.normalize()
        store.layout = layout
        store.flush()
        router.currentPage = 0
        Haptics.success()
        onFinished?()
        dismiss()
    }
}

extension UIImage {
    /// Redraws the image so its pixel data is upright (crop rects then match what the user sees).
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
