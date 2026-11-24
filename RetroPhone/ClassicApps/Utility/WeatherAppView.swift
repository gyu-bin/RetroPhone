import SwiftUI
import CoreLocation

/// iOS 4 Weather: a glossy rounded card (blue by day, purple by night) on a dark backdrop.
/// The "i" button flips the card to its settings side (unit, location).
/// Data: Open-Meteo (CC BY 4.0) via WeatherService.
struct WeatherAppView: View {
    @Environment(AppRouter.self) private var router
    @State private var angle: Double = 0
    @State private var showBack = false
    @State private var settingAtFlip: WeatherLocationSetting?
    private var service: WeatherService { .shared }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2A2C30), Color(hex: 0x070708)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Group {
                if showBack {
                    WeatherBackSide(done: { flip() })
                } else {
                    WeatherFrontSide(flip: { flip() })
                }
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .retroStatusBar(.black)
        .onAppear {
            if router.pendingDeepLink == .weather { router.pendingDeepLink = nil }
            // Opening the Weather app is the moment the location prompt may appear; the widget's
            // background refresh never prompts and leaves `.needsPermission`.
            if service.status != .loading,
               service.snapshot == nil || service.isStale || service.status == .needsPermission {
                service.refresh()
            }
        }
        .onChange(of: router.pendingDeepLink) { _, link in
            if link == .weather { router.pendingDeepLink = nil }
        }
    }

    /// Two-phase flip: rotate to edge-on, swap faces, rotate back in.
    private func flip() {
        SoundService.shared.play(.tock)
        let goingToBack = !showBack
        if goingToBack { settingAtFlip = SettingsStore.shared.value.weatherLocation }
        withAnimation(.easeIn(duration: 0.22)) {
            angle = 90
        } completion: {
            showBack = goingToBack
            angle = -90
            withAnimation(.easeOut(duration: 0.22)) { angle = 0 }
            if !goingToBack {
                let now = SettingsStore.shared.value.weatherLocation
                if now != settingAtFlip || service.snapshot == nil { service.refresh() }
            }
        }
    }
}

// MARK: - Card chrome

private struct WeatherCardBackground: View {
    var isDay: Bool
    var body: some View {
        ZStack {
            LinearGradient(colors: isDay ? [Color(hex: 0x62B4F4), Color(hex: 0x2F78D2), Color(hex: 0x1B4FA8)]
                                         : [Color(hex: 0x6B5A9E), Color(hex: 0x3F2F72), Color(hex: 0x21173F)],
                           startPoint: .top, endPoint: .bottom)
            // Gloss: a soft elliptical highlight over the top of the card.
            GeometryReader { geo in
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                    .frame(width: geo.size.width * 1.6, height: 230)
                    .position(x: geo.size.width / 2, y: 30)
            }
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.8), radius: 10, y: 4)
    }
}

private struct InfoButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("i")
                .font(.custom("Georgia-BoldItalic", fixedSize: 16))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(L("날씨 설정"))
    }
}

// MARK: - Front

private struct WeatherFrontSide: View {
    var flip: () -> Void
    private var service: WeatherService { .shared }

    var body: some View {
        let snap = service.snapshot
        ZStack {
            WeatherCardBackground(isDay: snap?.isDay ?? true)
            VStack(spacing: 0) {
                if let snap {
                    ScrollView {
                        content(snap)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                } else {
                    placeholder
                }
                footer(snap)
            }
        }
    }

    // MARK: Snapshot content

    private func content(_ s: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            statusBanner
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    EmbossedText(text: s.placeName, size: 24)
                    EmbossedText(text: L(s.condition.labelKo), size: 15, weight: .regular)
                    EmbossedText(text: "\(L("최고")) \(s.high.temperatureString)  \(L("최저")) \(s.low.temperatureString)",
                                 size: 14)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    WeatherGlyph(condition: s.condition, isDay: s.isDay, size: 66)
                    Text(s.temperature.temperatureString)
                        .font(.retroFixed(58, .regular))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .accessibilityElement(children: .combine)

            if !s.hourly.isEmpty { hourlyStrip(s) }

            VStack(spacing: 0) {
                ForEach(Array(s.daily.prefix(6).enumerated()), id: \.element.id) { idx, day in
                    dayRow(day, isToday: idx == 0 && Calendar.current.isDateInToday(day.date))
                    if idx < min(6, s.daily.count) - 1 {
                        Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.16)))

            HStack(spacing: 16) {
                Label(s.sunrise.map { RetroFormat.time($0) } ?? "--", systemImage: "sunrise.fill")
                    .accessibilityLabel("\(L("일출")) \(s.sunrise.map { RetroFormat.time($0) } ?? "--")")
                Label(s.sunset.map { RetroFormat.time($0) } ?? "--", systemImage: "sunset.fill")
                    .accessibilityLabel("\(L("일몰")) \(s.sunset.map { RetroFormat.time($0) } ?? "--")")
                Spacer(minLength: 0)
            }
            .font(.retroFixed(13, .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func hourlyStrip(_ s: WeatherSnapshot) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(s.hourly.enumerated()), id: \.element.id) { idx, hour in
                    VStack(spacing: 3) {
                        EmbossedText(text: idx == 0 && hour.time <= Date() ? L("지금") : RetroFormat.date(hour.time, template: "j"), size: 11)
                        WeatherGlyph(condition: hour.condition, isDay: hour.isDay, size: 26)
                        EmbossedText(text: hour.temperature.temperatureString, size: 14)
                    }
                    .frame(width: 52)
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.16)))
    }

    private func dayRow(_ day: WeatherSnapshot.Day, isToday: Bool) -> some View {
        HStack(spacing: 8) {
            EmbossedText(text: isToday ? L("오늘") : RetroFormat.date(day.date, template: "EEEE"), size: 16)
            Spacer(minLength: 4)
            WeatherGlyph(condition: day.condition, size: 28)
            EmbossedText(text: day.high.temperatureString, size: 16)
                .frame(width: 44, alignment: .trailing)
            EmbossedText(text: day.low.temperatureString, size: 16, color: Color(hex: 0xC4D9F5))
                .frame(width: 44, alignment: .trailing)
        }
        .frame(height: 40)
        .accessibilityElement(children: .combine)
    }

    /// Stale / offline / error note above the data when the cached snapshot is shown.
    @ViewBuilder private var statusBanner: some View {
        let note = bannerText
        if let note {
            HStack(spacing: 6) {
                if service.status == .loading {
                    ProgressView().tint(.white).scaleEffect(0.7)
                } else {
                    Image(systemName: NetworkMonitor.shared.isOnline ? "exclamationmark.circle" : "wifi.slash")
                }
                Text(note).lineLimit(2)
            }
            .font(.retroFixed(12, .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.28)))
        }
    }

    private var bannerText: String? {
        switch service.status {
        case .loading:
            return L("업데이트 중…")
        case .failed(let message):
            return NetworkMonitor.shared.isOnline
                ? "\(message) · \(L("저장된 정보를 표시합니다"))"
                : "\(L("오프라인")) · \(L("저장된 정보를 표시합니다"))"
        case .locationDenied:
            return L("위치 권한이 꺼져 있어 저장된 정보를 표시합니다")
        default:
            if !NetworkMonitor.shared.isOnline { return "\(L("오프라인")) · \(L("저장된 정보를 표시합니다"))" }
            return service.isStale ? L("오래된 정보입니다") : nil
        }
    }

    // MARK: Placeholder (no snapshot yet)

    @ViewBuilder private var placeholder: some View {
        VStack(spacing: 14) {
            Spacer()
            WeatherGlyph(condition: .partlyCloudy, size: 80)
            switch service.status {
            case .locationDenied:
                EmbossedText(text: L("위치 권한이 필요합니다"), size: 18)
                Text(L("iOS 설정에서 위치 접근을 허용하거나, 뒷면에서 도시를 지정하세요."))
                    .font(.retroFixed(14))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
                GlossyButton(title: L("설정 열기"), tint: .gray) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .frame(maxWidth: 220)
                GlossyButton(title: L("도시 선택"), tint: .blue) { flip() }
                    .frame(maxWidth: 220)
            case .needsPermission:
                EmbossedText(text: L("위치 권한이 필요합니다"), size: 18)
                GlossyButton(title: L("현재 위치 사용"), tint: .blue) { service.refresh() }
                    .frame(maxWidth: 220)
                GlossyButton(title: L("도시 선택"), tint: .gray) { flip() }
                    .frame(maxWidth: 220)
            case .failed(let message):
                EmbossedText(text: message, size: 16)
                GlossyButton(title: L("다시 시도"), tint: .gray) { service.refresh() }
                    .frame(maxWidth: 220)
                GlossyButton(title: L("도시 선택"), tint: .blue) { flip() }
                    .frame(maxWidth: 220)
            default:
                ProgressView().tint(.white)
                EmbossedText(text: L("날씨 불러오는 중…"), size: 15)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private func footer(_ snap: WeatherSnapshot?) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Button {
                SoundService.shared.play(.tock)
                service.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PressDimStyle())
            .disabled(service.status == .loading)
            .accessibilityLabel(L("새로 고침"))

            VStack(spacing: 1) {
                if let snap {
                    Text(LF("업데이트: %@", RetroFormat.date(snap.fetchedAt, template: "MMMd") + " " + RetroFormat.time(snap.fetchedAt)))
                }
                Text(L("데이터: Open-Meteo (CC BY 4.0)"))
            }
            .font(.retroFixed(10, .bold))
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
            .frame(maxWidth: .infinity)
            .onTapGesture {
                if let url = URL(string: "https://open-meteo.com/") { UIApplication.shared.open(url) }
            }

            InfoButton(action: flip)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}

// MARK: - Back (settings)

private struct WeatherBackSide: View {
    var done: () -> Void
    @State var query = ""
    @State var results: [CityResult] = []
    @State var searching = false
    @State var searchedOnce = false
    @State var searchTask: Task<Void, Never>?

    struct CityResult: Identifiable {
        let id = UUID()
        var name: String
        var coordinate: CLLocationCoordinate2D
    }

    private var settings: SettingsStore { .shared }
    private var unitBinding: Binding<TemperatureUnit> {
        Binding(get: { SettingsStore.shared.value.temperatureUnit },
                set: { SettingsStore.shared.value.temperatureUnit = $0 })
    }

    var body: some View {
        ZStack {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x5D6C82), Color(hex: 0x2E3746)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 0) {
                    LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                    Spacer()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.8), radius: 10, y: 4)

            VStack(spacing: 0) {
                ZStack {
                    EmbossedText(text: L("날씨"), size: 20)
                    HStack {
                        Spacer()
                        ClassicBarButton(title: L("완료"), kind: .done) { done() }
                    }
                }
                .frame(height: 50)
                .padding(.horizontal, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionTitle(L("단위"))
                        RetroSegmented(options: [(TemperatureUnit.celsius, "°C"), (TemperatureUnit.fahrenheit, "°F")],
                                       selection: unitBinding)
                            .padding(.horizontal, 4)

                        sectionTitle(L("위치"))
                        locationList

                        sectionTitle(L("도시 검색"))
                        searchField
                        resultsList
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.immediately)

                Text(L("데이터: Open-Meteo (CC BY 4.0)"))
                    .font(.retroFixed(10, .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 10)
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.retroFixed(15, .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
    }

    private var locationList: some View {
        let setting = settings.value.weatherLocation
        return VStack(spacing: 0) {
            Button {
                Haptics.selection()
                settings.value.weatherLocation = .current
                LocationService.shared.requestPermission()
            } label: {
                checkRow(title: L("현재 위치"), subtitle: LocationService.shared.isDenied ? L("위치 권한이 꺼져 있습니다") : nil,
                         systemImage: "location.fill", checked: setting == .current)
            }
            .buttonStyle(.plain)
            if case .city(let name, _, _) = setting {
                Rectangle().fill(Color(hex: 0xD9D9D9)).frame(height: 1)
                checkRow(title: name, subtitle: nil, systemImage: "building.2.fill", checked: true)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(hex: 0x8A8F96), lineWidth: 1))
    }

    private func checkRow(title: String, subtitle: String?, systemImage: String, checked: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(Color(hex: 0x385487)).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.retro(16, .bold)).foregroundStyle(.black).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.retro(12)).foregroundStyle(Color(hex: 0xB8160B)).lineLimit(1)
                }
            }
            Spacer()
            if checked {
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Color(hex: 0x385487))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color(hex: 0x8A8A8A))
            TextField(L("도시 이름"), text: $query)
                .font(.retro(15))
                .foregroundStyle(.black)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { search() }
            if searching {
                ProgressView().scaleEffect(0.8)
            } else if !query.isEmpty {
                Button { query = ""; results = []; searchedOnce = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color(hex: 0xA0A0A0))
                }
                .accessibilityLabel(L("지우기"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().stroke(Color(hex: 0x8A96A6), lineWidth: 1))
    }

    @ViewBuilder private var resultsList: some View {
        if !results.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { idx, city in
                    Button {
                        Haptics.selection()
                        settings.value.weatherLocation = .city(name: city.name,
                                                               latitude: city.coordinate.latitude,
                                                               longitude: city.coordinate.longitude)
                        results = []
                        query = ""
                        searchedOnce = false
                    } label: {
                        HStack {
                            Text(city.name).font(.retro(16, .bold)).foregroundStyle(.black).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.2f, %.2f", city.coordinate.latitude, city.coordinate.longitude))
                                .font(.retro(11)).foregroundStyle(Color(hex: 0x7A7A7A))
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if idx < results.count - 1 { Rectangle().fill(Color(hex: 0xD9D9D9)).frame(height: 1) }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(hex: 0x8A8F96), lineWidth: 1))
        } else if searchedOnce && !searching {
            Text(NetworkMonitor.shared.isOnline ? L("검색 결과가 없습니다") : L("네트워크에 연결되어 있지 않습니다"))
                .font(.retroFixed(13))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searchTask?.cancel()
        searching = true
        searchTask = Task {
            let found = await WeatherService.searchCity(q)
            guard !Task.isCancelled else { return }
            results = found.map { CityResult(name: $0.name, coordinate: $0.coordinate) }
            searching = false
            searchedOnce = true
        }
    }
}
