import SwiftUI
import PhotosUI

/// First-run setup. iOS does not let apps read the real home-screen arrangement, so the user
/// rebuilds it here from screenshots (or starts from defaults plus detected apps) and can edit later.
struct SetupFlowView: View {
    @Environment(AppRouter.self) private var router
    enum Step: Int { case welcome, apps, wallpaper, done }
    @State private var step: Step = .welcome
    @State private var selectedExternal: Set<AppID> = []
    @State private var installed: [ExternalApp] = []
    @State private var showImport = false
    @State private var imported = false
    @State private var wallpaperItem: PhotosPickerItem?

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
        .onChange(of: wallpaperItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
                      let file = FileStore.saveImage(img, maxDimension: 2400) else { return }
                settings.value.homeWallpaper = .custom(file: file)
                settings.value.lockWallpaper = .custom(file: file)
            }
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
            GroupedSection(header: L("내 아이폰 그대로 (권장)"),
                           footer: imported ? L("가져온 배치가 적용되었습니다. 홈 화면에서 언제든 편집할 수 있습니다.")
                                            : L("실제 홈 화면을 페이지마다 스크린샷으로 찍어 두었다가 선택하면, 앱 이름과 위치를 기기 안에서 읽어 지금 쓰는 홈 화면을 2010년 스타일로 똑같이 만듭니다.")) {
                Button { showImport = true } label: {
                    TableRow(title: imported ? L("다시 가져오기…") : L("내 홈 화면 가져오기…"), systemIcon: "photo.stack", chevron: true,
                             accessory: { if imported { Image(systemName: "checkmark").foregroundStyle(Color(hex: 0x385487)) } })
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("setupImportHome")
            }
            GroupedSection(header: L("이 기기에 설치된 앱"),
                           footer: L("RetroPhone이 아는 앱 중 이 기기에 설치된 것을 기기 안에서 찾았습니다. 선택한 앱은 홈 화면에 추가됩니다.")) {
                if installed.isEmpty {
                    TableRow(title: L("찾은 앱 없음"))
                }
                ForEach(installed) { ext in
                    Button {
                        if selectedExternal.contains(ext.id) { selectedExternal.remove(ext.id) } else { selectedExternal.insert(ext.id) }
                    } label: {
                        TableRow(title: ext.displayName, icon: ext.art, accessory: {
                            if selectedExternal.contains(ext.id) {
                                Image(systemName: "checkmark").foregroundStyle(Color(hex: 0x385487))
                            }
                        })
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("setup.\(ext.id.raw)")
                }
            }
        }
        .task {
            guard installed.isEmpty else { return }
            installed = ExternalAppLauncher.installedCatalogApps()
            selectedExternal = Set(installed.map(\.id))
        }
        .fullScreenCover(isPresented: $showImport) {
            HomeImportView(onFinished: { imported = true })
        }
    }

    private var wallpaper: some View {
        VStack(spacing: 0) {
        GroupedSection(header: L("내 배경화면")) {
            PhotosPicker(selection: $wallpaperItem, matching: .images) {
                TableRow(title: L("사진에서 선택…"), systemIcon: "photo.on.rectangle", chevron: true, accessory: {
                    if case .custom = settings.value.homeWallpaper { Image(systemName: "checkmark").foregroundStyle(Color(hex: 0x385487)) }
                })
            }
        }
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
        // An imported layout is kept as-is; otherwise start from the default layout.
        var layout = imported ? store.layout : HomeLayout.default
        for ext in installed where selectedExternal.contains(ext.id) { layout.addApp(ext.id) }
        store.layout = layout
        store.flush()
        settings.value.setupCompleted = true
        router.currentPage = 0
        withAnimation(.easeInOut(duration: 0.4)) { router.screen = .lock }
    }

}
