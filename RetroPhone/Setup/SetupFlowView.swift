import SwiftUI
import PhotosUI

/// First-run setup. iOS does not let apps read the real home-screen arrangement, so the user
/// builds their layout here (from defaults, a checklist, or a screenshot draft) and can edit later.
struct SetupFlowView: View {
    @Environment(AppRouter.self) private var router
    enum Step: Int { case welcome, apps, wallpaper, done }
    @State private var step: Step = .welcome
    @State private var selectedExternal: Set<AppID> = []
    @State private var draft: ScreenshotLayoutImporter.Draft?
    @State private var photoItem: PhotosPickerItem?
    @State private var analyzing = false
    @State private var importError = false

    private var settings: SettingsStore { SettingsStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            ClassicNavBar(title: title, leading: {
                if step != .welcome {
                    ClassicBarButton(title: L("뒤로"), kind: .back) { go(Step(rawValue: step.rawValue - 1) ?? .welcome) }
                }
            }, trailing: {
                ClassicBarButton(title: step == .done ? L("시작") : L("다음"), kind: .done) { next() }
                    .accessibilityIdentifier("setupNext")
            })
            ScrollView {
                VStack(spacing: 0) {
                    switch step {
                    case .welcome: welcome
                    case .apps: apps
                    case .wallpaper: wallpaper
                    case .done: done
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .background(PinstripeBackground().ignoresSafeArea())
        .retroAlert(L("스크린샷을 분석하지 못했습니다"), isPresented: $importError, message: L("홈 화면 스크린샷인지 확인하세요."))
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await analyze(item) }
        }
    }

    private var title: String {
        switch step {
        case .welcome: L("환영합니다")
        case .apps: L("홈 화면 구성")
        case .wallpaper: L("배경화면")
        case .done: L("준비 완료")
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            RetroIconView(art: .phone, size: 96).padding(.top, 30)
            Text("RetroPhone").font(.retro(28, .bold)).foregroundStyle(Color(hex: 0x2A3442)).embossed().padding(.top, 14)
            Text(L("최신 아이폰에서 2010년의 아이폰을 사용해 보세요."))
                .font(.retro(16)).foregroundStyle(Color(hex: 0x4C566C)).embossed()
                .multilineTextAlignment(.center).padding(.horizontal, 30).padding(.top, 6)
            GroupedSection(header: L("언어")) {
                ForEach(AppLanguage.allCases) { lang in
                    Button { settings.value.language = lang } label: {
                        TableRow(title: lang.displayName, accessory: {
                            if settings.value.language == lang { Image(systemName: "checkmark").foregroundStyle(Color(hex: 0x385487)) }
                        })
                    }.buttonStyle(.plain)
                }
            }
            Text(L("RetroPhone의 잠금화면은 앱 안의 가상 화면이며 기기 보안(암호·Face ID)과 무관합니다. 사용자 데이터는 기기 밖으로 전송되지 않습니다. (날씨 조회 시 대략적인 좌표만 날씨 서비스로 전송)"))
                .font(.retro(14)).foregroundStyle(Color(hex: 0x4C566C)).embossed()
                .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 14)
        }
    }

    private var apps: some View {
        VStack(spacing: 0) {
            GroupedSection(header: L("스크린샷에서 가져오기 (베타)"),
                           footer: L("실제 홈 화면 스크린샷의 앱 이름을 기기 안에서 인식해 배치 초안을 만듭니다. 아이콘·위젯·폴더 내용은 인식하지 못하므로 결과를 확인하고 수정하세요.")) {
                PhotosPicker(selection: $photoItem, matching: .screenshots) {
                    TableRow(title: analyzing ? L("분석 중…") : L("스크린샷 선택…"), systemIcon: "text.viewfinder", chevron: true)
                }
                .disabled(analyzing)
                if let draft {
                    TableRow(title: L("인식된 앱"), detail: "\(draft.pageApps.count + draft.dockApps.count)")
                    if !draft.unmatched.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("지원하지 않거나 인식하지 못한 이름")).font(.retro(13, .bold))
                            Text(draft.unmatched.prefix(20).joined(separator: ", ")).font(.retro(13)).foregroundStyle(Color(hex: 0x6A6A6A))
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { self.draft = nil } label: { TableRow(title: L("초안 버리기"), destructive: true) }.buttonStyle(.plain)
                }
            }
            GroupedSection(header: L("외부 앱 추가"), footer: L("선택한 앱은 홈 화면 마지막 페이지에 추가됩니다. 앱이 설치되어 있지 않으면 웹 또는 App Store로 연결됩니다.")) {
                ForEach(AppCatalog.externalApps) { ext in
                    Button {
                        if selectedExternal.contains(ext.id) { selectedExternal.remove(ext.id) } else { selectedExternal.insert(ext.id) }
                    } label: {
                        TableRow(title: ext.displayName, icon: ext.art, accessory: {
                            if selectedExternal.contains(ext.id) || draftContains(ext.id) {
                                Image(systemName: "checkmark").foregroundStyle(Color(hex: 0x385487))
                            }
                        })
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("setup.\(ext.id.raw)")
                }
            }
        }
    }

    private func draftContains(_ id: AppID) -> Bool {
        guard let draft else { return false }
        return draft.pageApps.contains(id) || draft.dockApps.contains(id)
    }

    private var wallpaper: some View {
        GroupedSection(header: L("잠금화면과 홈 화면")) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(BuiltinWallpaper.allCases) { w in
                    let selected = settings.value.homeWallpaper == .builtin(w)
                    VStack(spacing: 4) {
                        WallpaperView(choice: .builtin(w))
                            .frame(width: 88, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0x2F6BDB), lineWidth: selected ? 3 : 0))
                        Text(w.displayName).font(.retro(13, .bold))
                    }
                    .onTapGesture {
                        settings.value.homeWallpaper = .builtin(w)
                        settings.value.lockWallpaper = .builtin(w)
                    }
                }
            }
            .padding(10)
        }
    }

    private var done: some View {
        VStack(spacing: 12) {
            RetroIconView(art: .settings, size: 80).padding(.top, 40)
            Text(L("모든 준비가 끝났습니다.")).font(.retro(20, .bold)).embossed()
            Text(L("홈 화면의 아이콘을 길게 누르면 편집할 수 있고, 아래의 가상 홈 버튼을 두 번 누르면 멀티태스킹이 열립니다. 언제든 화면 아래에서 위로 쓸어 올려 실제 iOS로 돌아갈 수 있습니다."))
                .font(.retro(15)).foregroundStyle(Color(hex: 0x4C566C)).embossed()
                .multilineTextAlignment(.center).padding(.horizontal, 30)
        }
    }

    private func go(_ s: Step) {
        SoundService.shared.play(.tock)
        withAnimation(.easeInOut(duration: 0.25)) { step = s }
    }

    private func next() {
        switch step {
        case .welcome: go(.apps)
        case .apps: go(.wallpaper)
        case .wallpaper: go(.done)
        case .done: finish()
        }
    }

    private func finish() {
        let store = LayoutStore.shared
        var layout = draft.map { ScreenshotLayoutImporter.layout(from: $0) } ?? HomeLayout.default
        // Keep catalog order for added apps.
        for ext in AppCatalog.externalApps where selectedExternal.contains(ext.id) { layout.addApp(ext.id) }
        store.layout = layout
        store.flush()
        settings.value.setupCompleted = true
        router.currentPage = 0
        withAnimation(.easeInOut(duration: 0.4)) { router.screen = .lock }
    }

    private func analyze(_ item: PhotosPickerItem) async {
        analyzing = true
        defer { analyzing = false }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
              let labels = try? await ScreenshotLayoutImporter.recognizeLabels(in: image) else {
            importError = true
            return
        }
        let d = ScreenshotLayoutImporter.draft(from: labels)
        if d.pageApps.isEmpty && d.dockApps.isEmpty { importError = true; return }
        draft = d
        Haptics.success()
    }
}
