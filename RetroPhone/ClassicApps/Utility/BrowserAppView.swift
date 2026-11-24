import SwiftUI
import WebKit

/// iOS 4 style web browser (WKWebView). Gray-blue top bar with address + search fields,
/// blue bottom toolbar with back / forward / share / bookmarks / pages.
struct BrowserAppView: View {
    @State private var session = BrowserSession()
    @State private var addressText = ""
    @State private var searchText = ""
    @State private var engine = SearchEngine.current
    @State private var showBookmarks = false
    @State private var showPages = false
    @FocusState private var focus: Field?

    enum Field: Hashable { case address, search }

    var body: some View {
        let tab = session.current
        ZStack {
            VStack(spacing: 0) {
                topBar(tab)
                    .zIndex(1)
                content(tab)
                bottomToolbar(tab)
            }
            if showPages {
                BrowserPagesView(session: session, onDone: { withAnimation(.easeInOut(duration: 0.25)) { showPages = false } },
                                 onNewPage: { openNewPage() })
                    .transition(.opacity.combined(with: .scale(scale: 1.08)))
                    .zIndex(2)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .onChange(of: focus) { _, newValue in
            if newValue == .address { addressText = BrowserURL.displayString(for: session.current.url) }
        }
        .sheet(isPresented: $showBookmarks) {
            BrowserBookmarksView(currentTab: session.current, engine: $engine) { url in
                session.current.load(url)
            }
        }
    }

    // MARK: Top bar

    private func topBar(_ tab: BrowserTab) -> some View {
        VStack(spacing: 3) {
            Text(tab.url == nil ? L("브라우저") : tab.displayTitle)
                .font(.retroFixed(13, .bold))
                .foregroundStyle(Color(hex: 0x2B3647))
                .shadow(color: .white.opacity(0.6), radius: 0, y: 1)
                .lineLimit(1)
                .padding(.horizontal, 24)
            HStack(spacing: 6) {
                addressField(tab)
                if focus != .address {
                    searchField
                        .frame(width: focus == .search ? 190 : 112)
                }
                if focus != nil {
                    ClassicBarButton(title: L("취소")) { focus = nil }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 3)
        .padding(.bottom, 6)
        .background(
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(hex: 0xCBD3DD), Color(hex: 0xA9B5C4), Color(hex: 0x8D9BAE)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color(hex: 0x4B5566)).frame(height: 1)
            }
        )
        .animation(.easeOut(duration: 0.2), value: focus)
    }

    private var addressBinding: Binding<String> {
        Binding(
            get: { focus == .address ? addressText : BrowserURL.displayString(for: session.current.url) },
            set: { addressText = $0 }
        )
    }

    private func addressField(_ tab: BrowserTab) -> some View {
        HStack(spacing: 4) {
            TextField(L("주소 입력"), text: addressBinding)
                .font(.retroFixed(14))
                .foregroundStyle(Color(hex: 0x222222))
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focus, equals: .address)
                .onSubmit { go(addressText) }
            if focus == .address {
                if !addressText.isEmpty {
                    Button { addressText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color(hex: 0xA0A0A0))
                    }
                    .accessibilityLabel(L("지우기"))
                }
            } else if tab.url != nil {
                Button {
                    SoundService.shared.play(.tock)
                    if tab.isLoading { tab.stop() } else { tab.reload() }
                } label: {
                    Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x4A5568))
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel(tab.isLoading ? L("중단") : L("새로 고침"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(
            ZStack(alignment: .leading) {
                Color.white
                if tab.isLoading && focus != .address {
                    GeometryReader { g in
                        LinearGradient(colors: [Color(hex: 0xC4DCFB), Color(hex: 0x7DB0F2)], startPoint: .top, endPoint: .bottom)
                            .frame(width: g.size.width * min(1, max(0.06, tab.progress)))
                            .animation(.linear(duration: 0.2), value: tab.progress)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        )
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(hex: 0x66748A), lineWidth: 1))
        .shadow(color: .white.opacity(0.5), radius: 0, y: 1)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: 0x8A8A8A))
            TextField(engine.displayName, text: $searchText)
                .font(.retroFixed(14))
                .foregroundStyle(Color(hex: 0x222222))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focus, equals: .search)
                .onSubmit { search(searchText) }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().stroke(Color(hex: 0x66748A), lineWidth: 1))
        .shadow(color: .white.opacity(0.5), radius: 0, y: 1)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ tab: BrowserTab) -> some View {
        ZStack {
            BrowserWebContainer(tab: tab)
            if let error = tab.loadError {
                BrowserErrorPage(message: error, url: tab.failedURL) { tab.reload() }
            } else if tab.url == nil {
                BrowserStartPage(offline: !NetworkMonitor.shared.isOnline) { url in tab.load(url) }
            }
            if focus != nil {
                Color.black.opacity(0.4)
                    .contentShape(Rectangle())
                    .onTapGesture { focus = nil }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Bottom toolbar

    private func bottomToolbar(_ tab: BrowserTab) -> some View {
        ClassicToolbar(style: .blue) {
            ToolbarIconButton(systemImage: "arrowtriangle.left.fill", label: L("뒤로"), enabled: tab.canGoBack) { tab.goBack() }
            Spacer()
            ToolbarIconButton(systemImage: "arrowtriangle.right.fill", label: L("앞으로"), enabled: tab.canGoForward) { tab.goForward() }
            Spacer()
            shareButton(tab)
            Spacer()
            ToolbarIconButton(systemImage: "book", label: L("북마크")) {
                focus = nil
                showBookmarks = true
            }
            Spacer()
            pagesButton
        }
    }

    @ViewBuilder
    private func shareButton(_ tab: BrowserTab) -> some View {
        if let url = tab.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            ShareLink(item: url) {
                toolbarGlyph("square.and.arrow.up")
            }
            .accessibilityLabel(L("공유"))
        } else {
            toolbarGlyph("square.and.arrow.up").opacity(0.4).accessibilityLabel(L("공유"))
        }
    }

    private var pagesButton: some View {
        Button {
            SoundService.shared.play(.tock)
            focus = nil
            Task {
                await session.current.captureSnapshot()
                withAnimation(.easeInOut(duration: 0.25)) { showPages = true }
            }
        } label: {
            ZStack {
                toolbarGlyph("square.on.square")
                Text("\(session.tabs.count)")
                    .font(.retroFixed(10, .bold))
                    .foregroundStyle(.white)
                    .offset(x: 2.5, y: 3)
            }
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(LF("페이지 %d개", session.tabs.count))
    }

    private func toolbarGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
            .frame(width: 44, height: 40)
    }

    // MARK: Actions

    private func go(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        focus = nil
        guard !trimmed.isEmpty else { return }
        session.current.load(BrowserURL.resolve(trimmed, engine: engine))
    }

    private func search(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        focus = nil
        guard !q.isEmpty else { return }
        session.current.load(engine.searchURL(for: q))
    }

    private func openNewPage() {
        guard session.newTab() != nil else { return }
        withAnimation(.easeInOut(duration: 0.25)) { showPages = false }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            focus = .address
        }
    }
}

// MARK: - WKWebView host

/// Hosts the current page's WKWebView. Each `BrowserTab` owns its web view (so pages keep their
/// state) and acts as its navigation/KVO coordinator; this representable swaps the embedded view.
struct BrowserWebContainer: UIViewRepresentable {
    let tab: BrowserTab

    final class Coordinator {
        var embeddedID: UUID?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .white
        embed(in: container, coordinator: context.coordinator)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if context.coordinator.embeddedID != tab.id || tab.webView.superview !== uiView {
            embed(in: uiView, coordinator: context.coordinator)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        uiView.subviews.forEach { $0.removeFromSuperview() }
        coordinator.embeddedID = nil
    }

    private func embed(in container: UIView, coordinator: Coordinator) {
        container.subviews.forEach { $0.removeFromSuperview() }
        let web = tab.webView
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        coordinator.embeddedID = tab.id
    }
}

// MARK: - Start / error pages

private struct BrowserStartPage: View {
    var offline: Bool
    var open: (URL) -> Void
    private var store: BrowserBookmarkStore { .shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: offline ? "wifi.slash" : "globe")
                    .font(.system(size: 52))
                    .foregroundStyle(Color(hex: 0x9AA4B2))
                    .shadow(color: .white, radius: 0, y: 1)
                    .padding(.top, 40)
                Text(offline ? L("네트워크에 연결되어 있지 않습니다") : L("주소를 입력하거나 검색하세요"))
                    .font(.retro(16, .bold))
                    .foregroundStyle(Color(hex: 0x5A6474))
                    .multilineTextAlignment(.center)
                    .embossed()
                if !store.items.isEmpty {
                    GroupedSection(header: L("북마크")) {
                        ForEach(store.items.prefix(8)) { bookmark in
                            Button { open(bookmark.url) } label: {
                                TableRow(title: bookmark.title, systemIcon: "book")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PinstripeBackground())
    }
}

private struct BrowserErrorPage: View {
    var message: String
    var url: URL?
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: NetworkMonitor.shared.isOnline ? "exclamationmark.triangle" : "wifi.slash")
                .font(.system(size: 50))
                .foregroundStyle(Color(hex: 0x8A94A4))
                .shadow(color: .white, radius: 0, y: 1)
            Text(L("페이지를 열 수 없음"))
                .font(.retro(20, .bold))
                .foregroundStyle(Color(hex: 0x4C566C))
                .embossed()
            Text(message)
                .font(.retro(15))
                .foregroundStyle(Color(hex: 0x4C566C))
                .multilineTextAlignment(.center)
                .embossed()
            if let host = url?.host {
                Text(host).font(.retro(13)).foregroundStyle(Color(hex: 0x7A8494)).lineLimit(1)
            }
            GlossyButton(title: L("다시 시도"), tint: .gray, action: retry)
                .frame(maxWidth: 220)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PinstripeBackground())
    }
}

// MARK: - Pages (tabs) overview

private struct BrowserPagesView: View {
    let session: BrowserSession
    var onDone: () -> Void
    var onNewPage: () -> Void
    @State private var selection: UUID

    init(session: BrowserSession, onDone: @escaping () -> Void, onNewPage: @escaping () -> Void) {
        self.session = session
        self.onDone = onDone
        self.onNewPage = onNewPage
        _selection = State(initialValue: session.currentID)
    }

    var body: some View {
        let selectedTab = session.tabs.first { $0.id == selection }
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(selectedTab.map { $0.url == nil ? L("새로운 페이지") : $0.displayTitle } ?? "")
                    .font(.retroFixed(16, .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 0, y: -1)
                    .lineLimit(1)
                Text(BrowserURL.displayString(for: selectedTab?.url))
                    .font(.retroFixed(12))
                    .foregroundStyle(Color(hex: 0xC9D2DE))
                    .lineLimit(1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .frame(height: 64)

            TabView(selection: $selection) {
                ForEach(session.tabs) { tab in
                    card(tab)
                        .tag(tab.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            ClassicToolbar(style: .blue) {
                ClassicBarButton(title: L("새로운 페이지")) { onNewPage() }
                    .disabled(!session.canAddTab)
                    .opacity(session.canAddTab ? 1 : 0.5)
                Spacer()
                ClassicBarButton(title: L("완료"), kind: .done) {
                    session.currentID = selection
                    onDone()
                }
            }
        }
        .background(
            LinearGradient(colors: [Color(hex: 0x5B6878), Color(hex: 0x2B323C)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .onChange(of: session.tabs.map(\.id)) { _, ids in
            if !ids.contains(selection) { selection = session.currentID }
        }
    }

    private func card(_ tab: BrowserTab) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let image = tab.snapshot {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ZStack {
                        Color.white
                        Image(systemName: "globe").font(.system(size: 44)).foregroundStyle(Color(hex: 0xB8C0CC))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
            .contentShape(Rectangle())
            .onTapGesture {
                SoundService.shared.play(.tock)
                session.currentID = tab.id
                onDone()
            }

            Button {
                SoundService.shared.play(.tock)
                withAnimation(.easeInOut(duration: 0.2)) { session.close(tab.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(LinearGradient(colors: [Color(hex: 0xF0645A), Color(hex: 0xB3140B)], startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
            .buttonStyle(PressDimStyle())
            .offset(x: -12, y: -12)
            .accessibilityLabel(L("페이지 닫기"))
        }
        .padding(.horizontal, 44)
        .padding(.top, 16)
        .padding(.bottom, 48)
    }
}

// MARK: - Bookmarks

private struct BrowserBookmarksView: View {
    let currentTab: BrowserTab
    @Binding var engine: SearchEngine
    var onOpen: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State var editing = false
    private var store: BrowserBookmarkStore { .shared }

    var body: some View {
        NavigationStack {
            ClassicPage(title: L("북마크"), background: AnyView(Color.white), leading: {
                ClassicBarButton(title: editing ? L("완료") : L("편집"), kind: editing ? .done : .plain) {
                    withAnimation { editing.toggle() }
                }
            }, trailing: {
                ClassicBarButton(title: L("닫기")) { dismiss() }
            }) {
                VStack(spacing: 0) {
                    List {
                        NavigationLink {
                            SearchEnginePickerView(engine: $engine)
                        } label: {
                            HStack {
                                Image(systemName: "magnifyingglass").foregroundStyle(Color(hex: 0x385487)).frame(width: 26)
                                Text(L("검색 엔진")).font(.retro(17, .bold))
                                Spacer()
                                Text(engine.displayName).font(.retro(15)).foregroundStyle(Color(hex: 0x385487))
                            }
                        }
                        if store.items.isEmpty {
                            Text(L("북마크 없음"))
                                .font(.retro(15))
                                .foregroundStyle(Color(hex: 0x8A8A8A))
                        }
                        ForEach(store.items) { bookmark in
                            Button {
                                onOpen(bookmark.url)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "book").foregroundStyle(Color(hex: 0x385487)).frame(width: 26)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(bookmark.title).font(.retro(17, .bold)).foregroundStyle(.black).lineLimit(1)
                                        Text(bookmark.url.host ?? bookmark.url.absoluteString)
                                            .font(.retro(12)).foregroundStyle(Color(hex: 0x7A7A7A)).lineLimit(1)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { store.items[$0].id }
                            ids.forEach { store.delete($0) }
                        }
                        .onMove { source, destination in
                            store.move(fromOffsets: source, toOffset: destination)
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, .constant(editing ? .active : .inactive))

                    ClassicToolbar(style: .blue) {
                        let already = store.contains(currentTab.url)
                        let canAdd = currentTab.url != nil && currentTab.loadError == nil && !already
                        ClassicBarButton(title: already ? L("북마크됨") : L("현재 페이지 추가")) {
                            if let url = currentTab.url { store.add(title: currentTab.title, url: url) }
                            Haptics.success()
                        }
                        .disabled(!canAdd)
                        .opacity(canAdd ? 1 : 0.5)
                        Spacer()
                    }
                }
            }
        }
    }
}

private struct SearchEnginePickerView: View {
    @Environment(\.retroTheme) private var theme
    @Binding var engine: SearchEngine

    var body: some View {
        ClassicPage(title: L("검색 엔진"), leading: { ClassicBackButton() }, trailing: { EmptyView() }) {
            ScrollView {
                GroupedSection(footer: L("검색 필드에서 사용할 검색 엔진을 선택하세요.")) {
                    ForEach(SearchEngine.allCases) { option in
                        Button {
                            Haptics.selection()
                            engine = option
                            SearchEngine.current = option
                        } label: {
                            TableRow(title: option.displayName)
                                .overlay(alignment: .trailing) {
                                    if engine == option {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(theme.detailText)
                                            .padding(.trailing, 12)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
