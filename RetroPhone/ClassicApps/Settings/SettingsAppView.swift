import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import Contacts
import EventKit
import MediaPlayer
import Photos
import UserNotifications

/// RetroPhone preferences, styled like iOS 4 Settings. These settings only affect RetroPhone;
/// it never changes system settings.
struct SettingsAppView: View {
    @Environment(AppRouter.self) private var router
    private var settings: SettingsStore { SettingsStore.shared }

    var body: some View {
        NavigationStack {
            ClassicPage(title: L("설정"), leading: { EmptyView() }, trailing: { EmptyView() }) {
                ScrollView {
                    VStack(spacing: 0) {
                        GroupedSection {
                            link(L("스타일"), icon: .phone, detail: settings.value.themeEra == .ios7 ? "iOS 7" : "iOS 4") { StyleSettingsView() }
                        }
                        GroupedSection {
                            link(L("배경화면"), icon: .photos) { WallpaperSettingsView() }
                            link(L("홈 화면"), icon: .generic) { HomeSettingsView() }
                            link(L("잠금 화면"), icon: .clock) { LockSettingsView() }
                        }
                        GroupedSection {
                            link(L("소리 및 햅틱"), icon: .music) { SoundSettingsView() }
                            link(L("글자 크기"), icon: .notes) { TextSizeSettingsView() }
                            link(L("언어"), icon: .globe, detail: settings.value.language.displayName) { LanguageSettingsView() }
                            link(L("날씨"), icon: .weather) { WeatherSettingsView() }
                        }
                        GroupedSection {
                            link(L("개인정보 및 접근 권한"), icon: .heart) { PrivacySettingsView() }
                            link(L("레이아웃 백업 및 복원"), icon: .book) { BackupSettingsView() }
                            link(L("정보"), icon: .settings) { AboutSettingsView() }
                        }
                        GroupedSection(footer: L("RetroPhone은 시스템 홈 화면을 대체하지 않습니다. 화면 하단에서 위로 쓸어 올리면 언제든 실제 iOS로 돌아갈 수 있습니다.")) {
                            link(L("실제 iOS 환경으로 돌아가기"), icon: .phone) { ReturnToIOSView() }
                        }
                        Color.clear.frame(height: 30)
                    }
                }
            }
        }
    }

    private func link<D: View>(_ title: String, icon: IconArt, detail: String? = nil, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            TableRow(title: title, detail: detail, icon: icon, chevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.\(title)")
    }
}

/// Sub-page scaffold with back button.
/// Which iPhone era RetroPhone recreates: iOS 4 on iPhone 4 or iOS 7 on iPhone 5s.
struct StyleSettingsView: View {
    @Environment(\.retroTheme) private var theme
    var body: some View {
        let current = SettingsStore.shared.value.themeEra
        SettingsPage(title: L("스타일")) {
            GroupedSection(footer: L("홈 화면·잠금 화면·상태 표시줄·아이콘·메뉴 모양이 바뀝니다. 기본 배경화면을 쓰고 있으면 그 시대의 배경화면으로 함께 바뀝니다.")) {
                ForEach(ThemeEra.allCases) { era in
                    Button { Self.apply(era) } label: {
                        TableRow(title: era.displayName) {
                            if era == current {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(theme.isFlat ? theme.tint : Color(hex: 0x385487))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(era == current ? .isSelected : [])
                }
            }
        }
    }

    /// Switches era; built-in default wallpapers follow the era, custom ones are kept.
    static func apply(_ era: ThemeEra) {
        var value = SettingsStore.shared.value
        guard value.themeEra != era else { return }
        let oldDefault = WallpaperChoice.builtin(value.themeEra.defaultWallpaper)
        let newDefault = WallpaperChoice.builtin(era.defaultWallpaper)
        if value.homeWallpaper == oldDefault { value.homeWallpaper = newDefault }
        if value.lockWallpaper == oldDefault { value.lockWallpaper = newDefault }
        value.themeEra = era
        Haptics.selection()
        withAnimation(.easeInOut(duration: 0.3)) { SettingsStore.shared.value = value }
    }
}

struct SettingsPage<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        ClassicPage(title: title, leading: { ClassicBackButton(title: L("설정")) }, trailing: { EmptyView() }) {
            ScrollView { VStack(spacing: 0) { content(); Color.clear.frame(height: 30) } }
        }
    }
}

private struct ToggleRow: View {
    var title: String
    @Binding var isOn: Bool
    var body: some View {
        TableRow(title: title, accessory: { RetroToggle(isOn: $isOn, label: title) })
    }
}

private struct CheckRow: View {
    var title: String
    var checked: Bool
    var action: () -> Void
    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            TableRow(title: title, accessory: {
                if checked { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Color(hex: 0x385487)) }
            })
        }
        .buttonStyle(.plain)
    }
}

private func binding<T>(_ keyPath: WritableKeyPath<RetroSettings, T>) -> Binding<T> {
    Binding(get: { SettingsStore.shared.value[keyPath: keyPath] },
            set: { SettingsStore.shared.value[keyPath: keyPath] = $0 })
}

// MARK: - Wallpaper

struct WallpaperSettingsView: View {
    enum Target: Hashable { case both, lock, home }
    @State private var target: Target = .both
    @State private var photoItem: PhotosPickerItem?
    private var settings: SettingsStore { SettingsStore.shared }

    var body: some View {
        SettingsPage(title: L("배경화면")) {
            HStack(spacing: 16) {
                preview(settings.value.lockWallpaper, L("잠금 화면"))
                preview(settings.value.homeWallpaper, L("홈 화면"))
            }
            .padding(.top, 16)
            RetroSegmented(options: [(Target.both, L("모두")), (.lock, L("잠금 화면")), (.home, L("홈 화면"))], selection: $target)
                .padding(.horizontal, 10).padding(.top, 14)
            GroupedSection(header: L("기본 배경화면")) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    ForEach(BuiltinWallpaper.allCases) { w in
                        VStack(spacing: 3) {
                            WallpaperView(choice: .builtin(w)).frame(width: 80, height: 130).clipShape(RoundedRectangle(cornerRadius: 5))
                            Text(w.displayName).font(.retro(12, .bold))
                        }
                        .onTapGesture { apply(.builtin(w)) }
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(10)
            }
            GroupedSection(header: L("사진")) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    TableRow(title: L("사진에서 선택…"), systemIcon: "photo.on.rectangle", chevron: true)
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
                      let file = FileStore.saveImage(img, maxDimension: 2400) else { return }
                apply(.custom(file: file))
            }
        }
    }

    private func preview(_ choice: WallpaperChoice, _ label: String) -> some View {
        VStack(spacing: 4) {
            WallpaperView(choice: choice).frame(width: 110, height: 190).clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.4), lineWidth: 1))
            Text(label).font(.retro(13, .bold)).foregroundStyle(Color(hex: 0x4C566C)).embossed()
        }
    }

    private func apply(_ choice: WallpaperChoice) {
        Haptics.success()
        let old = [settings.value.lockWallpaper, settings.value.homeWallpaper]
        if target != .home { settings.value.lockWallpaper = choice }
        if target != .lock { settings.value.homeWallpaper = choice }
        // Remove custom images that are no longer used.
        for case .custom(let file) in old where settings.value.lockWallpaper != .custom(file: file) && settings.value.homeWallpaper != .custom(file: file) {
            FileStore.deleteImage(file)
        }
    }
}

// MARK: - Home screen

struct HomeSettingsView: View {
    @Environment(AppRouter.self) private var router
    @State private var showAdd = false
    @State private var showImport = false
    @State private var confirmReset = false
    @State private var confirmIcons = false
    private var store: LayoutStore { LayoutStore.shared }

    var body: some View {
        SettingsPage(title: L("홈 화면")) {
            GroupedSection(footer: L("홈 화면에서 아이콘을 길게 눌러도 편집 모드가 시작됩니다. 편집 중 아이콘을 탭하면 이름과 아이콘을 바꿀 수 있습니다.")) {
                Button {
                    router.homePressed()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { withAnimation { router.isEditingHome = true } }
                } label: { TableRow(title: L("홈 화면 편집"), chevron: true) }.buttonStyle(.plain)
                Button { showAdd = true } label: { TableRow(title: L("앱·위젯 추가"), chevron: true) }.buttonStyle(.plain)
                Button { showImport = true } label: { TableRow(title: L("내 아이폰 홈 화면 가져오기"), systemIcon: "photo.stack", chevron: true) }.buttonStyle(.plain)
                ToggleRow(title: L("클래식 베젤 (위·아래)"), isOn: binding(\.classicBezel))
                ToggleRow(title: L("가상 홈 버튼 표시"), isOn: binding(\.showHomeButton))
            }
            GroupedSection(header: L("위젯")) {
                let widgets = store.layout.pages.enumerated().flatMap { p, items in items.compactMap { i in i.widget.map { (p, i.id, $0) } } }
                if widgets.isEmpty { TableRow(title: L("위젯 없음")) }
                ForEach(widgets, id: \.1) { page, id, spec in
                    TableRow(title: spec.kind.displayName, detail: "\(spec.size.label) · \(LF("%d페이지", page + 1))", accessory: {
                        Button { withAnimation { store.update { $0.remove(id) } } } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 22)).foregroundStyle(Color(hex: 0xD8261A))
                        }.buttonStyle(.plain).accessibilityLabel(L("위젯 제거"))
                    })
                }
            }
            GroupedSection(header: L("외부 앱"), footer: L("'설치됨' 여부는 iOS의 canOpenURL로 확인한 결과입니다. 설치된 앱 전체 목록은 iOS가 제공하지 않습니다.")) {
                ForEach(AppCatalog.externalApps + store.layout.customApps) { ext in
                    NavigationLink { ExternalAppDetailView(appID: ext.id) } label: {
                        TableRow(title: store.name(for: ext.id), detail: availabilityText(ext), icon: store.art(for: ext.id), chevron: true)
                    }.buttonStyle(.plain)
                }
            }
            GroupedSection(header: L("아이콘 테마"), footer: L("iOS 5·6 스타일은 테마 시스템에 추가될 예정입니다.")) {
                CheckRow(title: "iOS 4", checked: true) {}
                Button { confirmIcons = true } label: { TableRow(title: L("모든 아이콘 사용자화 초기화"), destructive: true) }.buttonStyle(.plain)
            }
            GroupedSection {
                Button { confirmReset = true } label: { TableRow(title: L("홈 화면 배치 초기화"), destructive: true) }.buttonStyle(.plain)
            }
        }
        .fullScreenCover(isPresented: $showAdd) { AddToHomeSheet().retroModalChrome() }
        .fullScreenCover(isPresented: $showImport) { HomeImportView() }
        .retroAlert(L("홈 화면 배치를 초기화할까요?"), isPresented: $confirmReset, message: L("폴더와 위치가 기본값으로 돌아갑니다. 추가한 바로가기는 유지됩니다."),
                    buttons: [RetroAlertButton(title: L("취소")), RetroAlertButton(title: L("초기화"), isPreferred: true) {
                        store.update { l in
                            let custom = l.customApps, overrides = l.overrides
                            l = .default
                            l.customApps = custom
                            l.overrides = overrides
                        }
                        router.currentPage = 0
                    }])
        .retroAlert(L("아이콘 사용자화를 모두 초기화할까요?"), isPresented: $confirmIcons,
                    buttons: [RetroAlertButton(title: L("취소")), RetroAlertButton(title: L("초기화"), isPreferred: true) {
                        for o in store.layout.overrides.values { if let f = o.customIconFile { FileStore.deleteImage(f) } }
                        store.update { $0.overrides = [:] }
                    }])
    }

    private func availabilityText(_ ext: ExternalApp) -> String {
        if ext.isSystem == true { return L("iOS 앱") }
        if ext.scheme == nil && ext.webURL == nil { return L("주소 없음") }
        return switch ExternalAppLauncher.availability(of: ext) {
        case .installed: L("설치됨")
        case .notInstalled: L("미설치")
        case .unknown: L("웹 링크")
        }
    }
}

struct ExternalAppDetailView: View {
    var appID: AppID
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false
    private var store: LayoutStore { LayoutStore.shared }

    var body: some View {
        let ext = store.external(appID)
        SettingsPage(title: store.name(for: appID)) {
            if let ext {
                RetroIconView(art: store.art(for: appID), size: 72, customImage: store.customIcon(for: appID)).padding(.top, 20)
                GroupedSection {
                    TableRow(title: L("실행 방식"), detail: ext.scheme ?? L("웹 링크"))
                    if let web = ext.webURL { TableRow(title: L("대체 링크"), detail: URL(string: web)?.host() ?? web) }
                    TableRow(title: L("검증 상태"), detail: verification(ext.verification))
                    TableRow(title: L("홈 화면"), detail: store.layout.placedApps.contains(appID) ? L("있음") : L("없음"))
                }
                GroupedSection {
                    Button {
                        Task { if !(await ExternalAppLauncher.open(ext)) { failed = true } }
                    } label: { TableRow(title: L("지금 열어 보기")) }.buttonStyle(.plain)
                    if !store.layout.placedApps.contains(appID) {
                        Button { store.update { $0.addApp(appID) } } label: { TableRow(title: L("홈 화면에 추가")) }.buttonStyle(.plain)
                    }
                    if appID.raw.hasPrefix("custom.") {
                        Button {
                            store.update { l in
                                l.customApps.removeAll { $0.id == appID }
                                for (p, page) in l.pages.enumerated() { l.pages[p] = page.filter { $0.appID != appID } }
                                for (p, page) in l.pages.enumerated() {
                                    for (i, item) in page.enumerated() {
                                        if var f = item.folder { f.apps.removeAll { $0 == appID }; l.pages[p][i].content = .folder(f) }
                                    }
                                }
                                l.dock.removeAll { $0 == appID }
                                l.normalize()
                            }
                            dismiss()
                        } label: { TableRow(title: L("바로가기 삭제"), destructive: true) }.buttonStyle(.plain)
                    }
                }
                Text(L("외부 앱이 열리면 해당 앱으로 전환되며, 그 앱의 디자인은 바꿀 수 없습니다. RetroPhone으로 돌아오면 이전 홈 화면 상태가 그대로 복원됩니다."))
                    .font(.retro(13)).foregroundStyle(Color(hex: 0x4C566C)).embossed().multilineTextAlignment(.center).padding(20)
            }
        }
        .retroAlert(L("앱을 열 수 없습니다"), isPresented: $failed)
    }

    private func verification(_ v: SchemeVerification) -> String {
        switch v {
        case .documented: L("공식 문서 확인")
        case .community: L("비공식(변경될 수 있음)")
        case .webOnly: L("웹/유니버설 링크")
        }
    }
}

// MARK: - Lock screen

struct LockSettingsView: View {
    @Environment(AppRouter.self) private var router
    private var settings: SettingsStore { SettingsStore.shared }
    var body: some View {
        SettingsPage(title: L("잠금 화면")) {
            GroupedSection(footer: L("가상 잠금화면은 RetroPhone 안의 화면일 뿐 보안 기능이 아닙니다. 기기 보안은 iOS의 암호·Face ID를 사용하세요.")) {
                ToggleRow(title: L("실행 시 잠금화면 표시"), isOn: binding(\.lockOnLaunch))
                ToggleRow(title: L("24시간제"), isOn: binding(\.use24HourClock))
                ToggleRow(title: L("배터리 잔량(%) 표시"), isOn: binding(\.showBatteryPercentage))
            }
            GroupedSection(header: L("자동 가상 잠금"), footer: L("지정한 시간 동안 조작이 없으면 가상 잠금화면을 표시합니다. iOS 자동 잠금과는 별개입니다.")) {
                ForEach([0, 1, 2, 5, 10, 15], id: \.self) { m in
                    CheckRow(title: m == 0 ? L("안 함") : LF("%d분", m), checked: settings.value.autoLockMinutes == m) {
                        settings.value.autoLockMinutes = m
                    }
                }
            }
            GroupedSection {
                Button { router.lock() } label: { TableRow(title: L("지금 잠그기")) }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Sound

struct SoundSettingsView: View {
    var body: some View {
        SettingsPage(title: L("소리 및 햅틱")) {
            GroupedSection(footer: L("모든 효과음은 RetroPhone이 직접 합성한 소리입니다. 무음 모드에서는 재생되지 않습니다.")) {
                ToggleRow(title: L("효과음"), isOn: binding(\.soundEnabled))
                ToggleRow(title: L("키보드 클릭"), isOn: binding(\.keyboardClicks))
                ToggleRow(title: L("햅틱"), isOn: binding(\.hapticsEnabled))
            }
            GroupedSection(header: L("미리 듣기")) {
                ForEach([(SoundService.Effect.unlock, L("잠금 해제")), (.lock, L("잠금")), (.shutter, L("카메라 셔터")), (.keyClick, L("키보드")), (.tock, L("버튼"))], id: \.1) { effect, name in
                    Button { SoundService.shared.play(effect); Haptics.tap() } label: {
                        TableRow(title: name, systemIcon: "speaker.wave.2.fill")
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Text size

struct TextSizeSettingsView: View {
    private var settings: SettingsStore { SettingsStore.shared }
    var body: some View {
        SettingsPage(title: L("글자 크기")) {
            GroupedSection(footer: L("RetroPhone 앱 안의 글자 크기에 적용됩니다.")) {
                VStack(spacing: 12) {
                    Text(L("가나다라 ABC 123")).font(.retro(17, .bold))
                    HStack {
                        Text("A").font(.system(size: 13))
                        Slider(value: binding(\.textScale), in: 0.85...1.35, step: 0.05)
                        Text("A").font(.system(size: 22))
                    }
                    Text("\(Int((settings.value.textScale * 100).rounded()))%").font(.retro(13)).foregroundStyle(Color(hex: 0x385487))
                }
                .padding(14)
            }
        }
    }
}

// MARK: - Language

struct LanguageSettingsView: View {
    private var settings: SettingsStore { SettingsStore.shared }
    var body: some View {
        SettingsPage(title: L("언어")) {
            GroupedSection(footer: L("시스템 권한 요청 문구는 iOS 언어 설정을 따릅니다.")) {
                ForEach(AppLanguage.allCases) { lang in
                    CheckRow(title: lang.displayName, checked: settings.value.language == lang) { settings.value.language = lang }
                }
            }
        }
    }
}

// MARK: - Weather

struct WeatherSettingsView: View {
    @State private var query = ""
    @State private var results: [(name: String, lat: Double, lon: Double)] = []
    private var settings: SettingsStore { SettingsStore.shared }

    var body: some View {
        SettingsPage(title: L("날씨")) {
            GroupedSection(header: L("단위")) {
                CheckRow(title: L("섭씨 (°C)"), checked: settings.value.temperatureUnit == .celsius) { settings.value.temperatureUnit = .celsius }
                CheckRow(title: L("화씨 (°F)"), checked: settings.value.temperatureUnit == .fahrenheit) { settings.value.temperatureUnit = .fahrenheit }
            }
            GroupedSection(header: L("위치"), footer: L("날씨 데이터: Open-Meteo (CC BY 4.0). 요청 시 약 1km 단위로 반올림한 좌표만 전송됩니다.")) {
                CheckRow(title: L("현재 위치"), checked: settings.value.weatherLocation == .current) {
                    settings.value.weatherLocation = .current
                    WeatherService.shared.refresh()
                }
                if case .city(let name, _, _) = settings.value.weatherLocation {
                    CheckRow(title: name, checked: true) {}
                }
            }
            GroupedSection(header: L("도시 검색")) {
                HStack {
                    TextField(L("도시 이름"), text: $query).font(.retro(17)).submitLabel(.search).onSubmit(search)
                    Button(L("검색"), action: search).font(.retro(15, .bold))
                }
                .padding(.horizontal, 10).frame(minHeight: 44)
                ForEach(results.indices, id: \.self) { i in
                    let r = results[i]
                    Button {
                        settings.value.weatherLocation = .city(name: r.name, latitude: r.lat, longitude: r.lon)
                        results = []
                        query = ""
                        WeatherService.shared.refresh()
                    } label: { TableRow(title: r.name, chevron: true) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func search() {
        Task {
            let found = await WeatherService.searchCity(query)
            results = found.map { ($0.name, $0.coordinate.latitude, $0.coordinate.longitude) }
        }
    }
}

// MARK: - Privacy

struct PrivacySettingsView: View {
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    var body: some View {
        SettingsPage(title: L("개인정보 및 접근 권한")) {
            GroupedSection(header: L("접근 권한"), footer: L("권한은 해당 기능을 처음 사용할 때 요청합니다. 변경은 iOS 설정에서 할 수 있습니다.")) {
                TableRow(title: L("위치"), detail: locationText)
                TableRow(title: L("사진"), detail: photoText)
                TableRow(title: L("카메라"), detail: avText(.video))
                TableRow(title: L("마이크"), detail: micText)
                TableRow(title: L("연락처"), detail: contactsText)
                TableRow(title: L("캘린더"), detail: calendarText)
                TableRow(title: L("미디어 보관함"), detail: musicText)
                TableRow(title: L("알림"), detail: notificationText)
            }
            GroupedSection {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: { TableRow(title: L("iOS 설정에서 권한 변경"), chevron: true) }.buttonStyle(.plain)
            }
            GroupedSection(header: L("데이터 처리")) {
                Text(L("• 레이아웃·메모·설정은 이 기기의 앱 저장 공간에만 저장됩니다.\n• 연락처·사진·캘린더·음악은 기기에서 읽기만 하며 외부로 전송하지 않습니다.\n• 날씨 조회 시에만 반올림한 좌표를 Open-Meteo로 전송합니다.\n• 스크린샷 분석은 기기 안에서 처리됩니다.\n• 개인 정보는 로그에 기록하지 않습니다."))
                    .font(.retro(14)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    }

    private func label(granted: Bool, denied: Bool, limited: Bool = false) -> String {
        if limited { return L("제한됨") }
        if granted { return L("허용") }
        if denied { return L("거부") }
        return L("묻지 않음")
    }
    private var locationText: String {
        let s = LocationService.shared.authorization
        return label(granted: s == .authorizedWhenInUse || s == .authorizedAlways, denied: s == .denied || s == .restricted)
    }
    private var photoText: String {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return label(granted: s == .authorized, denied: s == .denied || s == .restricted, limited: s == .limited)
    }
    private func avText(_ type: AVMediaType) -> String {
        let s = AVCaptureDevice.authorizationStatus(for: type)
        return label(granted: s == .authorized, denied: s == .denied || s == .restricted)
    }
    private var micText: String {
        let p = AVAudioApplication.shared.recordPermission
        return label(granted: p == .granted, denied: p == .denied)
    }
    private var contactsText: String {
        let s = CNContactStore.authorizationStatus(for: .contacts)
        return label(granted: s == .authorized, denied: s == .denied || s == .restricted, limited: s == .limited)
    }
    private var calendarText: String {
        let s = EKEventStore.authorizationStatus(for: .event)
        return label(granted: s == .fullAccess, denied: s == .denied || s == .restricted, limited: s == .writeOnly)
    }
    private var musicText: String {
        let s = MPMediaLibrary.authorizationStatus()
        return label(granted: s == .authorized, denied: s == .denied || s == .restricted)
    }
    private var notificationText: String {
        label(granted: notificationStatus == .authorized || notificationStatus == .provisional, denied: notificationStatus == .denied)
    }
}

// MARK: - Backup

struct BackupSettingsView: View {
    @Environment(AppRouter.self) private var router
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var resultTitle = ""
    @State private var showResult = false
    @State private var confirmSetup = false

    var body: some View {
        SettingsPage(title: L("레이아웃 백업 및 복원")) {
            GroupedSection(footer: L("홈 화면 배치, 폴더, 위젯, 바로가기, 설정을 JSON 파일로 내보냅니다. 사진으로 만든 아이콘·배경화면 이미지는 포함되지 않습니다.")) {
                if let exportURL {
                    ShareLink(item: exportURL) { TableRow(title: L("백업 파일 공유…"), systemIcon: "square.and.arrow.up", chevron: true) }
                } else {
                    Button { makeExport() } label: { TableRow(title: L("백업 만들기"), systemIcon: "doc.badge.plus") }.buttonStyle(.plain)
                }
                Button { importing = true } label: { TableRow(title: L("백업에서 복원…"), systemIcon: "square.and.arrow.down", chevron: true) }.buttonStyle(.plain)
            }
            GroupedSection {
                Button { confirmSetup = true } label: { TableRow(title: L("초기 설정 다시 하기"), destructive: true) }.buttonStyle(.plain)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let backup = try LayoutStore.decodeBackup(Data(contentsOf: url))
                var settings = backup.settings
                settings.setupCompleted = true
                // Custom images are not in the backup; fall back to built-in wallpaper if missing.
                if case .custom(let f) = settings.homeWallpaper, FileStore.loadImage(f) == nil { settings.homeWallpaper = .builtin(.droplets) }
                if case .custom(let f) = settings.lockWallpaper, FileStore.loadImage(f) == nil { settings.lockWallpaper = .builtin(.droplets) }
                var layout = backup.layout
                for (k, o) in layout.overrides { if let f = o.customIconFile, FileStore.loadImage(f) == nil { layout.overrides[k]?.customIconFile = nil } }
                layout.normalize()
                LayoutStore.shared.layout = layout
                LayoutStore.shared.flush()
                SettingsStore.shared.value = settings
                router.currentPage = 0
                resultTitle = L("복원했습니다")
            } catch {
                resultTitle = L("올바른 백업 파일이 아닙니다")
            }
            showResult = true
        }
        .retroAlert(resultTitle, isPresented: $showResult)
        .retroAlert(L("초기 설정을 다시 할까요?"), isPresented: $confirmSetup, message: L("현재 홈 화면 배치는 설정 과정에서 새로 만들어집니다."),
                    buttons: [RetroAlertButton(title: L("취소")), RetroAlertButton(title: L("다시 하기"), isPreferred: true) {
                        SettingsStore.shared.value.setupCompleted = false
                        router.recents = []
                        withAnimation { router.screen = .setup }
                    }])
    }

    private func makeExport() {
        exportURL = try? LayoutStore.shared.exportBackup(settings: SettingsStore.shared.value)
        if exportURL == nil { resultTitle = L("백업을 만들지 못했습니다"); showResult = true }
    }
}

// MARK: - About / licenses

struct AboutSettingsView: View {
    var body: some View {
        SettingsPage(title: L("정보")) {
            GroupedSection {
                TableRow(title: L("이름"), detail: "RetroPhone")
                TableRow(title: L("버전"), detail: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                TableRow(title: L("디자인"), detail: "iOS 4 (2010)")
            }
            GroupedSection(header: L("라이선스 및 오픈소스 출처")) {
                licenseText(L("The OldOS Project"), "© Zane Kleinberg (@zzanehip) — Creative Commons Attribution 4.0 (CC BY 4.0). " + L("RetroPhone은 OldOS의 구조와 동작을 참고했으며, 코드는 새로 작성했습니다. OldOS에 포함된 Apple 원본 이미지·사운드는 사용하지 않았습니다."))
                licenseText(L("날씨 데이터"), "Open-Meteo.com — " + L("데이터 CC BY 4.0. 비상업적 개인 사용 기준의 무료 API를 사용합니다."))
                licenseText(L("아이콘·배경화면·효과음"), L("모든 아이콘, 배경화면, 효과음은 RetroPhone에서 코드로 직접 그리거나 합성한 독자 제작물입니다. 일부 아이콘 기호에 Apple SF Symbols를 사용합니다(Apple 플랫폼 앱 내 사용 허용 범위)."))
                licenseText(L("상표"), L("iPhone, iOS는 Apple Inc.의 상표입니다. 카카오톡, 네이버, 인스타그램, 유튜브 등 앱 이름은 각 소유자의 상표이며, RetroPhone은 이들과 제휴 관계가 없습니다. 외부 앱 아이콘은 브랜드 로고 대신 일반적인 사물로 재해석했습니다."))
            }
        }
    }

    private func licenseText(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.retro(15, .bold))
            Text(body).font(.retro(13)).foregroundStyle(Color(hex: 0x4A4A4A)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Return to iOS

struct ReturnToIOSView: View {
    var body: some View {
        SettingsPage(title: L("실제 iOS로 돌아가기")) {
            VStack(spacing: 14) {
                Image(systemName: "arrow.up.to.line.compact").font(.system(size: 48)).foregroundStyle(Color(hex: 0x4C566C))
                    .padding(.top, 30)
                Text(L("화면 맨 아래의 막대를 위로 쓸어 올리세요")).font(.retro(18, .bold)).embossed().multilineTextAlignment(.center)
                Text(L("iOS는 다른 앱이 홈 화면으로 강제 이동하는 기능을 공개하지 않습니다. RetroPhone은 시스템 홈 제스처를 막지 않으므로 언제든 실제 홈 화면으로 돌아갈 수 있고, 다시 열면 이전 상태가 복원됩니다."))
                    .font(.retro(14)).foregroundStyle(Color(hex: 0x4C566C)).embossed().multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                GlossyButton(title: L("iOS 설정 앱 열기"), tint: .gray) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .padding(.horizontal, 40)
            }
        }
    }
}
