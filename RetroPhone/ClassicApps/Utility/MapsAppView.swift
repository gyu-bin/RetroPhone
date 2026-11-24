import SwiftUI
import MapKit
import CoreLocation

/// iOS 4 Maps: search bar on top, map, blue toolbar with the locate arrow and a page-curl
/// "옵션" button that peels the map up to reveal map type / drop pin / traffic.
struct MapsAppView: View {
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var query = ""
    @State private var results: [MapPlace] = []
    @State private var showResultList = false
    @State private var selectedID: UUID?
    @State private var droppedPin: MapPlace?
    @State private var route: MKRoute?
    @State private var routeTarget: UUID?
    @State private var searching = false
    @State private var routing = false
    @State private var message: String?
    @State private var showMessage = false
    @State private var showDeniedAlert = false
    @State private var optionsShown = false
    @State private var styleChoice: MapStyleChoice = .standard
    @State private var showsTraffic = false
    @State private var trackMode: TrackMode = .none
    @State private var searchTask: Task<Void, Never>?

    enum TrackMode { case none, follow, heading }

    private var location: LocationService { .shared }
    private let optionsHeight: CGFloat = 230

    private var allPlaces: [MapPlace] { results + (droppedPin.map { [$0] } ?? []) }
    private var selectedPlace: MapPlace? { allPlaces.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .zIndex(2)
            ZStack(alignment: .bottom) {
                MapsOptionsPanel(style: $styleChoice, showsTraffic: $showsTraffic,
                                 dropPin: { dropPin() }, close: { setOptions(false) })
                    .frame(height: optionsHeight)
                mapLayer
                    .offset(y: optionsShown ? -optionsHeight : 0)
                    .shadow(color: .black.opacity(optionsShown ? 0.6 : 0), radius: 6, y: 3)
                if showResultList && !results.isEmpty {
                    resultList
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .clipped()
            bottomToolbar
                .zIndex(2)
        }
        .background(Color(hex: 0xE6E3DD).ignoresSafeArea())
        .onAppear {
            location.requestPermission()
            if location.authorization == .authorizedWhenInUse || location.authorization == .authorizedAlways {
                position = .userLocation(fallback: .automatic)
            }
        }
        .onChange(of: location.authorization) { _, status in
            if (status == .authorizedWhenInUse || status == .authorizedAlways) && results.isEmpty && droppedPin == nil {
                withAnimation { position = .userLocation(fallback: .automatic) }
            }
        }
        .onDisappear { searchTask?.cancel() }
        .retroAlert(L("위치 서비스 꺼짐"), isPresented: $showDeniedAlert,
                    message: L("현재 위치를 보려면 iOS 설정에서 위치 접근을 허용하세요. 검색은 계속 사용할 수 있습니다."),
                    buttons: [
                        RetroAlertButton(title: L("취소")),
                        RetroAlertButton(title: L("설정"), isPreferred: true, action: {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }),
                    ])
        .retroAlert(message ?? "", isPresented: $showMessage)
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 0) {
            RetroSearchBar(text: $query, placeholder: L("검색 또는 주소"))
                .onSubmit(of: .text) { runSearch() }
            if !results.isEmpty {
                Button {
                    SoundService.shared.play(.tock)
                    withAnimation(.easeOut(duration: 0.2)) { showResultList.toggle() }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 0, y: -1)
                        .frame(width: 40, height: 30)
                        .background(RoundedRectangle(cornerRadius: 5).fill(
                            LinearGradient(colors: [Color(hex: 0x8EA0BA), Color(hex: 0x4A6489)], startPoint: .top, endPoint: .bottom)))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(PressDimStyle())
                .padding(.trailing, 6)
                .frame(height: 44)
                .background(LinearGradient(colors: [Color(hex: 0xD0D7DF), Color(hex: 0xA8B4C2)], startPoint: .top, endPoint: .bottom))
                .accessibilityLabel(L("검색 결과 목록"))
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0x6D7A8C)).frame(height: 1) }
    }

    // MARK: Map

    private var mapLayer: some View {
        Map(position: $position) {
            UserAnnotation()
            if let route {
                MapPolyline(route)
                    .stroke(Color(hex: 0x3478F6).opacity(0.8), lineWidth: 6)
            }
            ForEach(allPlaces) { place in
                Annotation(coordinate: place.coordinate, anchor: .bottom) {
                    pinView(place)
                } label: {
                    EmptyView()
                }
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(currentMapStyle)
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            if !position.followsUserLocation && trackMode != .none { trackMode = .none }
        }
        .overlay(alignment: .bottomTrailing) { pageCurl }
        .overlay {
            // While the options are revealed, tapping the (lifted) map puts it back down.
            if optionsShown {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { setOptions(false) }
            }
        }
    }

    private var currentMapStyle: MapStyle {
        switch styleChoice {
        case .standard: .standard(showsTraffic: showsTraffic)
        case .satellite: .imagery
        case .hybrid: .hybrid(showsTraffic: showsTraffic)
        }
    }

    /// Folded corner drawn on the map's bottom-right, as on iOS 4.
    private var pageCurl: some View {
        PageCurlShape()
            .fill(LinearGradient(colors: [Color(hex: 0xF4F1EA), Color(hex: 0xB9B4AA)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 34, height: 34)
            .shadow(color: .black.opacity(0.35), radius: 2, x: -1, y: -1)
            .allowsHitTesting(false)
            .opacity(optionsShown ? 0 : 1)
    }

    private func pinView(_ place: MapPlace) -> some View {
        let selected = place.id == selectedID
        return VStack(spacing: 2) {
            if selected {
                callout(place)
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }
            ClassicMapPin(color: place.isDroppedPin ? .purple : .red)
                .onTapGesture {
                    SoundService.shared.play(.tock)
                    withAnimation(.spring(duration: 0.25)) { selectedID = selected ? nil : place.id }
                }
                .accessibilityLabel(place.name)
                .accessibilityAddTraits(.isButton)
        }
    }

    private func callout(_ place: MapPlace) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name)
                    .font(.retroFixed(15, .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let address = place.address, !address.isEmpty {
                    Text(address)
                        .font(.retroFixed(11))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 190, alignment: .leading)
            Button {
                SoundService.shared.play(.tock)
                Task { await showRoute(to: place) }
            } label: {
                Group {
                    if routing && routeTarget == place.id {
                        ProgressView().tint(.white)
                    } else {
                        Text(L("경로")).font(.retroFixed(12, .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 28)
                .background(RoundedRectangle(cornerRadius: 5).fill(
                    LinearGradient(colors: [Color(hex: 0x7AA3F2), Color(hex: 0x2D63DA)], startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(PressDimStyle())
            Button {
                SoundService.shared.play(.tock)
                openInMaps(place)
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.white, Color(hex: 0x2D63DA))
            }
            .buttonStyle(PressDimStyle())
            .accessibilityLabel(L("지도 앱에서 열기"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x4A4A4A, opacity: 0.95), Color(hex: 0x0E0E0E, opacity: 0.95)],
                                         startPoint: .top, endPoint: .bottom))
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 18)
                    Spacer(minLength: 0)
                }
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        .fixedSize()
    }

    // MARK: Result list

    private var resultList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(results) { place in
                    Button {
                        SoundService.shared.play(.tock)
                        select(place)
                    } label: {
                        PlainRow {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.name).font(.retro(16, .bold)).foregroundStyle(.black).lineLimit(1)
                                if let address = place.address {
                                    Text(address).font(.retro(12)).foregroundStyle(Color(hex: 0x7A7A7A)).lineLimit(1)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 280)
        .background(Color.white)
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }

    // MARK: Toolbar

    private var bottomToolbar: some View {
        ClassicToolbar(style: .blue) {
            Button {
                SoundService.shared.play(.tock)
                locate()
            } label: {
                Image(systemName: trackMode == .heading ? "location.north.line.fill" : (trackMode == .follow ? "location.fill" : "location"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 0, y: -1)
                    .frame(width: 40, height: 30)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(
                        LinearGradient(colors: trackMode == .none ? [Color(hex: 0x8EA0BA), Color(hex: 0x4A6489)]
                                                                  : [Color(hex: 0x7AA3F2), Color(hex: 0x2D63DA)],
                                       startPoint: .top, endPoint: .bottom)))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.black.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(PressDimStyle())
            .accessibilityLabel(L("현재 위치"))

            Spacer(minLength: 6)
            routeSummary
            Spacer(minLength: 6)

            Button {
                SoundService.shared.play(.tock)
                setOptions(!optionsShown)
            } label: {
                HStack(spacing: 4) {
                    PageCurlShape()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.4), radius: 0, y: -1)
                    Text(L("옵션")).font(.retroFixed(12.5, .bold))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 0, y: -1)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(
                    LinearGradient(colors: optionsShown ? [Color(hex: 0x7AA3F2), Color(hex: 0x2D63DA)]
                                                       : [Color(hex: 0x8EA0BA), Color(hex: 0x4A6489)],
                                   startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.black.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(PressDimStyle())
            .accessibilityLabel(L("옵션"))
        }
    }

    @ViewBuilder private var routeSummary: some View {
        if let route {
            HStack(spacing: 6) {
                VStack(spacing: 0) {
                    Text(Self.distanceString(route.distance))
                        .font(.retroFixed(13, .bold))
                    Text(Self.durationString(route.expectedTravelTime))
                        .font(.retroFixed(11))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 0, y: -1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Button {
                    SoundService.shared.play(.tock)
                    withAnimation { self.route = nil; routeTarget = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(.white.opacity(0.85))
                }
                .accessibilityLabel(L("경로 지우기"))
            }
        } else if searching {
            ProgressView().tint(.white)
        }
    }

    // MARK: Actions

    private func locate() {
        if location.isDenied {
            showDeniedAlert = true
            return
        }
        if location.authorization == .notDetermined {
            location.requestPermission()
            return
        }
        withAnimation(.easeInOut(duration: 0.4)) {
            switch trackMode {
            case .none:
                trackMode = .follow
                position = .userLocation(fallback: .automatic)
            case .follow:
                trackMode = .heading
                position = .userLocation(followsHeading: true, fallback: .automatic)
            case .heading:
                trackMode = .follow
                position = .userLocation(fallback: .automatic)
            }
        }
    }

    private func setOptions(_ shown: Bool) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { optionsShown = shown }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        guard NetworkMonitor.shared.isOnline else {
            present(L("네트워크에 연결되어 있지 않습니다"))
            return
        }
        searchTask?.cancel()
        searching = true
        let region = visibleRegion
        searchTask = Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = q
            if let region { request.region = region }
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                let places = response.mapItems.map { MapPlace(item: $0) }
                searching = false
                route = nil
                routeTarget = nil
                withAnimation(.easeOut(duration: 0.2)) {
                    results = places
                    showResultList = places.count > 1
                }
                if places.count == 1, let only = places.first {
                    select(only)
                } else if !places.isEmpty {
                    selectedID = nil
                    trackMode = .none
                    withAnimation { position = .region(response.boundingRegion) }
                }
            } catch is CancellationError {
                searching = false
            } catch {
                guard !Task.isCancelled else { return }
                searching = false
                present(L("검색 결과가 없습니다"))
            }
        }
    }

    private func select(_ place: MapPlace) {
        trackMode = .none
        withAnimation(.easeOut(duration: 0.2)) { showResultList = false }
        withAnimation(.easeInOut(duration: 0.5)) {
            selectedID = place.id
            position = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
        }
    }

    private func dropPin() {
        guard let center = visibleRegion?.center else { setOptions(false); return }
        let pin = MapPlace(droppedAt: center)
        droppedPin = pin
        selectedID = pin.id
        setOptions(false)
        Haptics.tap(.medium)
        Task {
            if let resolved = await MapPlace.reverseGeocoded(pin) {
                if droppedPin?.id == pin.id { droppedPin = resolved }
            }
        }
    }

    private func showRoute(to place: MapPlace) async {
        if location.isDenied || location.authorization == .notDetermined {
            // No in-app route without the user's location; hand off to the Maps app instead.
            if location.authorization == .notDetermined { location.requestPermission() }
            openInMaps(place)
            return
        }
        guard NetworkMonitor.shared.isOnline else {
            present(L("네트워크에 연결되어 있지 않습니다"))
            return
        }
        routing = true
        routeTarget = place.id
        defer { routing = false }
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = place.mapItem
        request.transportType = .automobile
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let first = response.routes.first else {
                present(L("경로를 찾을 수 없습니다"))
                return
            }
            trackMode = .none
            withAnimation(.easeInOut(duration: 0.5)) {
                route = first
                let rect = first.polyline.boundingMapRect
                position = .rect(rect.insetBy(dx: -rect.size.width * 0.15, dy: -rect.size.height * 0.25))
            }
        } catch {
            routeTarget = nil
            present(L("경로를 찾을 수 없습니다"))
        }
    }

    private func openInMaps(_ place: MapPlace) {
        place.mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    private func present(_ text: String) {
        message = text
        showMessage = true
    }

    // MARK: Formatting

    static func distanceString(_ meters: CLLocationDistance) -> String {
        let f = MKDistanceFormatter()
        f.locale = Localizer.shared.language.locale
        f.unitStyle = .abbreviated
        return f.string(fromDistance: meters)
    }

    static func durationString(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = Localizer.shared.language.locale
        f.calendar = calendar
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .short
        return f.string(from: max(60, seconds)) ?? ""
    }
}

// MARK: - Model

private enum MapStyleChoice: Hashable { case standard, satellite, hybrid }

private struct MapPlace: Identifiable {
    let id: UUID
    var name: String
    var address: String?
    var coordinate: CLLocationCoordinate2D
    var mapItem: MKMapItem
    var isDroppedPin = false

    init(item: MKMapItem) {
        id = UUID()
        mapItem = item
        coordinate = item.location.coordinate
        name = item.name ?? L("위치")
        address = item.address?.shortAddress ?? item.address?.fullAddress
            ?? item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
    }

    init(droppedAt coordinate: CLLocationCoordinate2D) {
        id = UUID()
        self.coordinate = coordinate
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        item.name = L("놓은 핀")
        mapItem = item
        name = L("놓은 핀")
        address = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        isDroppedPin = true
    }

    /// Resolves the dropped pin's address with MapKit's reverse geocoder (iOS 26 API).
    static func reverseGeocoded(_ pin: MapPlace) async -> MapPlace? {
        let loc = CLLocation(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: loc) else { return nil }
        request.preferredLocale = Localizer.shared.language.locale
        guard let items = try? await request.mapItems, let first = items.first else { return nil }
        var updated = pin
        let text = first.address?.shortAddress ?? first.address?.fullAddress
            ?? first.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
        if let text, !text.isEmpty { updated.address = text }
        let item = MKMapItem(location: loc, address: first.address)
        item.name = L("놓은 핀")
        updated.mapItem = item
        return updated
    }
}

// MARK: - Classic pin

private struct ClassicMapPin: View {
    enum PinColor { case red, purple, green }
    var color: PinColor

    private var colors: (Color, Color) {
        switch color {
        case .red: (Color(hex: 0xFF7A6E), Color(hex: 0xB0140A))
        case .purple: (Color(hex: 0xC59AF5), Color(hex: 0x6A2BB8))
        case .green: (Color(hex: 0x8BE07A), Color(hex: 0x1F8E14))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(RadialGradient(colors: [colors.0, colors.1], center: UnitPoint(x: 0.35, y: 0.3),
                                     startRadius: 0, endRadius: 10))
                .overlay(Circle().fill(Color.white.opacity(0.75)).frame(width: 4, height: 4).offset(x: -2.5, y: -2.5))
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
                .frame(width: 15, height: 15)
            Rectangle()
                .fill(LinearGradient(colors: [Color(hex: 0xE0E0E0), Color(hex: 0x7A7A7A)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 2, height: 22)
        }
        .shadow(color: .black.opacity(0.45), radius: 1.5, x: 2, y: 1)
        .frame(width: 30, height: 40, alignment: .bottom)
        .contentShape(Rectangle())
    }
}

/// A triangular folded page corner.
private struct PageCurlShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY), control: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.25))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Options panel (revealed under the curled map)

private struct MapsOptionsPanel: View {
    @Binding var style: MapStyleChoice
    @Binding var showsTraffic: Bool
    var dropPin: () -> Void
    var close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                GlossyButton(title: L("핀 꽂기"), systemImage: "mappin", tint: .gray, height: 40) { dropPin() }
                VStack(spacing: 4) {
                    Text(L("교통 정보"))
                        .font(.retroFixed(13, .bold))
                        .foregroundStyle(Color(hex: 0x3A3A3A))
                        .shadow(color: .white, radius: 0, y: 1)
                    RetroToggle(isOn: $showsTraffic, label: L("교통 정보"))
                }
                .opacity(style == .satellite ? 0.4 : 1)
                .disabled(style == .satellite)
            }
            RetroSegmented(options: [(MapStyleChoice.standard, L("표준")),
                                     (MapStyleChoice.satellite, L("위성")),
                                     (MapStyleChoice.hybrid, L("하이브리드"))],
                           selection: $style)
            Text(L("지도 데이터 © Apple 및 데이터 제공자"))
                .font(.retroFixed(10))
                .foregroundStyle(Color(hex: 0x6A6A6A))
                .padding(.bottom, 6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Color(hex: 0xD9D5CC)
                // Linen-like cross hatching.
                Canvas { ctx, size in
                    var x: CGFloat = 0
                    while x < size.width {
                        ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Color.black.opacity(0.035)))
                        x += 3
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color.white.opacity(0.08)))
                        y += 3
                    }
                }
            }
        )
    }
}
