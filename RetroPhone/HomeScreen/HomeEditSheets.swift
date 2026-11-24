import SwiftUI
import PhotosUI

/// Modal for adding apps (hidden built-ins, catalog external apps, custom URL apps) and widgets.
struct AddToHomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    enum Tab: Hashable { case apps, widgets, custom }
    @State private var tab: Tab = .apps
    @State private var customName = ""
    @State private var customURL = ""
    @State private var customArt: IconArt = .generic
    @State private var invalidURL = false

    private var store: LayoutStore { LayoutStore.shared }

    var body: some View {
        ClassicPage(title: L("홈 화면에 추가"), leading: { EmptyView() }, trailing: {
            ClassicBarButton(title: L("완료"), kind: .done) { dismiss() }
        }) {
            VStack(spacing: 0) {
                RetroSegmented(options: [(Tab.apps, L("앱")), (Tab.widgets, L("위젯")), (Tab.custom, L("직접 추가"))], selection: $tab)
                    .padding(10)
                ScrollView {
                    switch tab {
                    case .apps: appsList
                    case .widgets: widgetsList
                    case .custom: customForm
                    }
                    Color.clear.frame(height: 30)
                }
            }
        }
        .retroAlert(L("올바른 실행 주소가 아닙니다"), isPresented: $invalidURL, message: L("예: myapp:// 또는 https://example.com"))
    }

    private var appsList: some View {
        let placed = store.layout.placedApps
        let builtins = BuiltinApp.allCases.map(\.appID).filter { !placed.contains($0) }
        let externals = (AppCatalog.externalApps + store.layout.customApps).filter { !placed.contains($0.id) }
        return VStack(spacing: 0) {
            if !builtins.isEmpty {
                GroupedSection(header: L("내장 앱")) {
                    ForEach(builtins) { app in
                        addRow(app, detail: nil)
                    }
                }
            }
            GroupedSection(header: L("외부 앱"), footer: L("공식 URL 스킴 또는 웹 링크로 해당 앱을 엽니다. 설치 여부는 실행 시 확인됩니다.")) {
                if externals.isEmpty {
                    TableRow(title: L("모든 앱이 홈 화면에 있습니다"))
                }
                ForEach(externals) { ext in
                    addRow(ext.id, detail: verificationLabel(ext.verification))
                }
            }
        }
    }

    private func addRow(_ app: AppID, detail: String?) -> some View {
        Button {
            Haptics.success()
            withAnimation { store.update { $0.addApp(app) } }
        } label: {
            TableRow(title: store.name(for: app), detail: detail, accessory: {
                Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(Color(hex: 0x3BB83A))
            })
            .overlay(alignment: .leading) { EmptyView() }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("add.\(app.raw)")
    }

    private func verificationLabel(_ v: SchemeVerification) -> String {
        switch v {
        case .documented: L("공식 문서")
        case .community: L("비공식")
        case .webOnly: L("웹 링크")
        }
    }

    private var widgetsList: some View {
        VStack(spacing: 0) {
            ForEach(WidgetKind.allCases) { kind in
                GroupedSection(header: kind.displayName) {
                    HStack(spacing: 10) {
                        ForEach(kind.supportedSizes) { size in
                            Button {
                                Haptics.success()
                                withAnimation { store.update { $0.addWidget(.init(kind: kind, size: size), page: router.currentPage) } }
                                dismiss()
                            } label: {
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(LinearGradient(colors: [Color(hex: 0x8EA0BA), Color(hex: 0x4A6489)], startPoint: .top, endPoint: .bottom))
                                        .frame(width: CGFloat(size.columns) * 14, height: CGFloat(size.rows) * 14)
                                    Text(size.label).font(.retro(13, .bold)).foregroundStyle(Color(hex: 0x385487))
                                }
                                .frame(maxWidth: .infinity, minHeight: 80)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("addWidget.\(kind.rawValue).\(size.rawValue)")
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var customForm: some View {
        VStack(spacing: 0) {
            GroupedSection(header: L("새 바로가기"), footer: L("앱의 URL 스킴(예: myapp://) 또는 웹 주소를 입력하세요. 스킴이 동작하지 않으면 열리지 않을 수 있습니다.")) {
                HStack {
                    Text(L("이름")).font(.retro(17, .bold)).frame(width: 70, alignment: .leading)
                    TextField(L("앱 이름"), text: $customName).font(.retro(17))
                }.padding(.horizontal, 10).frame(minHeight: 44)
                HStack {
                    Text(L("주소")).font(.retro(17, .bold)).frame(width: 70, alignment: .leading)
                    TextField("myapp://", text: $customURL)
                        .font(.retro(17))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }.padding(.horizontal, 10).frame(minHeight: 44)
            }
            GroupedSection(header: L("아이콘")) {
                IconArtPicker(selection: $customArt).padding(8)
            }
            GlossyButton(title: L("홈 화면에 추가"), tint: .blue) { addCustom() }
                .padding(20)
        }
    }

    private func addCustom() {
        let name = customName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let url = ExternalAppLauncher.normalizedURL(customURL) else { invalidURL = true; return }
        let isWeb = url.hasPrefix("http")
        let app = ExternalApp(id: AppID("custom.\(UUID().uuidString)"), nameKo: name, nameEn: name,
                              scheme: isWeb ? nil : url, webURL: isWeb ? url : nil, appStoreID: nil,
                              verification: isWeb ? .webOnly : .community, art: customArt)
        store.update { l in
            l.customApps.append(app)
            l.addApp(app.id)
        }
        Haptics.success()
        dismiss()
    }
}

/// Grid of all icon artworks.
struct IconArtPicker: View {
    @Binding var selection: IconArt
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
            ForEach(IconArt.allCases) { art in
                RetroIconView(art: art, size: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: RetroIconView.cornerRadius(50) + 3)
                            .stroke(Color(hex: 0x2F6BDB), lineWidth: selection == art ? 3 : 0)
                            .padding(-4)
                    )
                    .onTapGesture { Haptics.selection(); selection = art }
                    .accessibilityLabel(art.rawValue)
                    .accessibilityAddTraits(selection == art ? .isSelected : [])
            }
        }
    }
}

/// Rename an app and change its icon (built-in art or a photo).
struct IconEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    var app: AppID
    @State private var name = ""
    @State private var art: IconArt = .generic
    @State private var photoItem: PhotosPickerItem?
    @State private var customFile: String?
    @State private var removeConfirm = false

    private var store: LayoutStore { LayoutStore.shared }

    var body: some View {
        ClassicPage(title: L("아이콘 편집"), leading: {
            ClassicBarButton(title: L("취소")) { dismiss() }
        }, trailing: {
            ClassicBarButton(title: L("저장"), kind: .done) { save() }
        }) {
            ScrollView {
                VStack(spacing: 0) {
                    RetroIconView(art: art, size: 90, customImage: customFile.flatMap(FileStore.loadImage))
                        .padding(.top, 20)
                    GroupedSection(header: L("이름")) {
                        TextField(AppCatalog.defaultName(app, custom: store.layout.customApps), text: $name)
                            .font(.retro(17))
                            .padding(.horizontal, 10).frame(minHeight: 44)
                            .accessibilityIdentifier("iconNameField")
                    }
                    GroupedSection(header: L("사진으로 아이콘 만들기")) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            TableRow(title: L("사진 선택…"), systemIcon: "photo", chevron: true)
                        }
                        if customFile != nil {
                            Button { customFile = nil } label: { TableRow(title: L("사진 아이콘 제거"), destructive: true) }
                                .buttonStyle(.plain)
                        }
                    }
                    GroupedSection(header: L("클래식 아이콘")) {
                        IconArtPicker(selection: $art).padding(8)
                    }
                    GroupedSection {
                        Button {
                            name = ""
                            art = AppCatalog.defaultArt(app, custom: store.layout.customApps)
                            customFile = nil
                        } label: { TableRow(title: L("기본값으로 되돌리기")) }
                        .buttonStyle(.plain)
                    }
                    Color.clear.frame(height: 30)
                }
            }
        }
        .onAppear {
            let o = store.layout.overrides[app.raw]
            name = o?.name ?? ""
            art = store.art(for: app)
            customFile = o?.customIconFile
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    customFile = FileStore.saveImage(img.squareCropped(), maxDimension: 240)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultArt = AppCatalog.defaultArt(app, custom: store.layout.customApps)
        store.setOverride(app) { o in
            o.name = trimmed.isEmpty ? nil : trimmed
            o.art = art == defaultArt ? nil : art
            if let old = o.customIconFile, old != customFile { FileStore.deleteImage(old) }
            o.customIconFile = customFile
        }
        Haptics.success()
        dismiss()
    }
}

/// Change a widget's size or remove it.
struct WidgetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    var itemID: UUID
    private var store: LayoutStore { LayoutStore.shared }

    var body: some View {
        let spec = store.layout.item(itemID)?.widget
        ClassicPage(title: spec?.kind.displayName ?? L("위젯"), leading: { EmptyView() }, trailing: {
            ClassicBarButton(title: L("완료"), kind: .done) { dismiss() }
        }) {
            ScrollView {
                if let spec {
                    VStack(spacing: 0) {
                        WidgetCell(spec: spec, size: CGSize(width: CGFloat(spec.size.columns) * 70, height: CGFloat(spec.size.rows) * 70), editing: false)
                            .allowsHitTesting(false)
                            .padding(.top, 20)
                        GroupedSection(header: L("크기")) {
                            ForEach(spec.kind.supportedSizes) { size in
                                Button {
                                    store.update { l in
                                        guard let loc = l.locate(itemID) else { return }
                                        l.pages[loc.page][loc.index].content = .widget(.init(kind: spec.kind, size: size))
                                        l.normalize()
                                    }
                                } label: {
                                    TableRow(title: size.label, accessory: {
                                        if size == spec.size { Image(systemName: "checkmark").foregroundStyle(Color(hex: 0x385487)) }
                                    })
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        GroupedSection {
                            Button {
                                store.update { $0.remove(itemID) }
                                dismiss()
                            } label: { TableRow(title: L("위젯 제거"), destructive: true) }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

extension UIImage {
    func squareCropped() -> UIImage {
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            draw(at: CGPoint(x: -origin.x, y: -origin.y))
        }
    }
}
