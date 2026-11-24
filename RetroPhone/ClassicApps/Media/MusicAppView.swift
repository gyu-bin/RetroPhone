import Combine
import MediaPlayer
import SwiftUI

// MARK: - Model

enum IPodTab: String, CaseIterable, Identifiable {
    case playlists, artists, songs, albums, more
    var id: String { rawValue }
    var title: String {
        switch self {
        case .playlists: L("재생목록")
        case .artists: L("아티스트")
        case .songs: L("노래")
        case .albums: L("앨범")
        case .more: L("더 보기")
        }
    }
    var systemImage: String {
        switch self {
        case .playlists: "music.note.list"
        case .artists: "music.mic"
        case .songs: "music.note"
        case .albums: "square.stack.fill"
        case .more: "ellipsis"
        }
    }
}

enum MusicGroupKind: Hashable {
    case genres, composers, compilations
    var title: String {
        switch self {
        case .genres: L("장르")
        case .composers: L("작곡가")
        case .compilations: L("컴필레이션")
        }
    }
}

enum MusicRoute: Hashable {
    case songs(title: String, collection: MPMediaItemCollection)
    case artist(MPMediaItemCollection)
    case album(MPMediaItemCollection)
    case groups(MusicGroupKind)
}

/// Lazily loaded snapshot of the user's local media library (only what MediaPlayer exposes).
@Observable
final class MusicLibraryCache {
    private(set) var playlists: [MPMediaItemCollection]?
    private(set) var artists: [MPMediaItemCollection]?
    private(set) var albums: [MPMediaItemCollection]?
    private(set) var songs: [MPMediaItem]?

    func ensure(_ tab: IPodTab) {
        let music = MusicService.shared
        guard music.isAuthorized else { return }
        switch tab {
        case .playlists: if playlists == nil { playlists = music.playlists() }
        case .artists: if artists == nil { artists = music.artists() }
        case .songs: if songs == nil { songs = music.songs() }
        case .albums: if albums == nil { albums = music.albums() }
        case .more: break
        }
    }

    func invalidate() {
        playlists = nil
        artists = nil
        albums = nil
        songs = nil
    }

    static func groups(_ kind: MusicGroupKind) -> [MPMediaItemCollection] {
        guard MusicService.shared.isAuthorized else { return [] }
        switch kind {
        case .genres: return MPMediaQuery.genres().collections ?? []
        case .composers: return MPMediaQuery.composers().collections ?? []
        case .compilations: return MPMediaQuery.compilations().collections ?? []
        }
    }
}

/// Navigation helpers shared by every iPod page.
struct MusicNav {
    var showNowPlaying: () -> Void

    func play(_ items: [MPMediaItem], startAt item: MPMediaItem? = nil, shuffle: Bool = false) {
        guard !items.isEmpty else { return }
        let music = MusicService.shared
        music.player.shuffleMode = shuffle ? .songs : .off
        music.play(items, startAt: shuffle ? nil : item)
        showNowPlaying()
    }
}

// MARK: - Root

struct MusicAppView: View {
    @State private var tab: IPodTab = .playlists
    @State private var showNowPlaying = false
    @State private var cache = MusicLibraryCache()

    var body: some View {
        let music = MusicService.shared
        let nav = MusicNav(showNowPlaying: {
            withAnimation(.easeInOut(duration: 0.35)) { showNowPlaying = true }
        })
        ZStack {
            VStack(spacing: 0) {
                content(music: music, nav: nav)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                IPodTabBar(selection: $tab)
            }
            if showNowPlaying {
                NowPlayingView {
                    withAnimation(.easeInOut(duration: 0.35)) { showNowPlaying = false }
                }
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .preference(key: StatusBarStyleKey.self, value: showNowPlaying ? StatusBarStyle.translucent : nil)
        .task {
            if !music.isAuthorized && !music.isDenied { await music.requestAccess() }
            music.refresh()
            if music.isAuthorized { MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .MPMediaLibraryDidChange).receive(on: DispatchQueue.main)) { _ in
            cache.invalidate()
        }
    }

    @ViewBuilder
    private func content(music: MusicService, nav: MusicNav) -> some View {
        if music.isAuthorized {
            switch tab {
            case .playlists:
                MusicNavigationRoot(nav: nav) { PlaylistsPage(cache: cache, nav: nav) }
            case .artists:
                MusicNavigationRoot(nav: nav) { ArtistsPage(cache: cache, nav: nav) }
            case .songs:
                MusicNavigationRoot(nav: nav) { SongsPage(cache: cache, nav: nav) }
            case .albums:
                MusicNavigationRoot(nav: nav) { AlbumsPage(cache: cache, nav: nav) }
            case .more:
                MusicNavigationRoot(nav: nav) { MorePage(nav: nav) }
            }
        } else {
            NavigationStack {
                ClassicPage(title: tab.title, leading: { EmptyView() }, trailing: { EmptyView() }) {
                    if music.isDenied {
                        PermissionPlaceholder(systemImage: "music.note", title: L("미디어 보관함 접근 권한이 필요합니다"),
                                              message: L("음악을 보고 재생하려면 iOS 설정에서 미디어 및 Apple Music 접근을 허용하세요."),
                                              denied: true)
                    } else {
                        PermissionPlaceholder(systemImage: "music.note", title: L("음악"),
                                              message: L("기기의 음악 보관함을 보려면 접근을 허용하세요."),
                                              requestTitle: L("접근 허용"),
                                              request: { Task { await music.requestAccess(); music.refresh() } })
                    }
                }
            }
        }
    }
}

struct MusicNavigationRoot<Content: View>: View {
    let nav: MusicNav
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .navigationDestination(for: MusicRoute.self) { route in
                    switch route {
                    case .songs(let title, let collection):
                        SongListPage(title: title, items: collection.items, nav: nav)
                    case .artist(let collection):
                        ArtistPage(collection: collection, nav: nav)
                    case .album(let collection):
                        AlbumPage(collection: collection, nav: nav)
                    case .groups(let kind):
                        GroupListPage(kind: kind, nav: nav)
                    }
                }
        }
    }
}

/// Plain white iOS 4 list page with the "Now Playing" button when something is playing.
struct MusicPage<Content: View>: View {
    var title: String
    var showsBack: Bool
    var nav: MusicNav
    @ViewBuilder var content: () -> Content

    var body: some View {
        ClassicPage(title: title, background: AnyView(Color.white),
                    leading: {
                        if showsBack { ClassicBackButton() }
                    },
                    trailing: {
                        if MusicService.shared.nowPlaying != nil {
                            NowPlayingBarButton(action: nav.showNowPlaying)
                        }
                    }) {
            content()
        }
    }
}

// MARK: - Tab pages

struct PlaylistsPage: View {
    let cache: MusicLibraryCache
    let nav: MusicNav

    var body: some View {
        MusicPage(title: L("재생목록"), showsBack: false, nav: nav) {
            if let playlists = cache.playlists {
                if playlists.isEmpty {
                    MusicEmptyNote(title: L("재생목록 없음"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(playlists.enumerated()), id: \.offset) { _, playlist in
                                let name = (playlist as? MPMediaPlaylist)?.name ?? L("재생목록")
                                NavigationLink(value: MusicRoute.songs(title: name, collection: playlist)) {
                                    MusicTextRow(title: name, detail: LF("%d곡", playlist.count))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                MusicLoading()
            }
        }
        .task { cache.ensure(.playlists) }
    }
}

struct ArtistsPage: View {
    let cache: MusicLibraryCache
    let nav: MusicNav

    var body: some View {
        MusicPage(title: L("아티스트"), showsBack: false, nav: nav) {
            if let artists = cache.artists {
                if artists.isEmpty {
                    MusicEmptyNote(title: L("보관함에 음악이 없습니다"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(artists.enumerated()), id: \.offset) { _, artist in
                                NavigationLink(value: MusicRoute.artist(artist)) {
                                    MusicArtworkRow(item: artist.representativeItem,
                                                    title: artist.representativeItem?.artist ?? L("알 수 없는 아티스트"),
                                                    subtitle: LF("%d곡", artist.count),
                                                    chevron: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                MusicLoading()
            }
        }
        .task { cache.ensure(.artists) }
    }
}

struct SongsPage: View {
    let cache: MusicLibraryCache
    let nav: MusicNav

    var body: some View {
        MusicPage(title: L("노래"), showsBack: false, nav: nav) {
            if let songs = cache.songs {
                if songs.isEmpty {
                    MusicEmptyNote(title: L("보관함에 음악이 없습니다"))
                } else {
                    SongList(items: songs, nav: nav, showsArtwork: true)
                }
            } else {
                MusicLoading()
            }
        }
        .task { cache.ensure(.songs) }
    }
}

struct AlbumsPage: View {
    let cache: MusicLibraryCache
    let nav: MusicNav

    var body: some View {
        MusicPage(title: L("앨범"), showsBack: false, nav: nav) {
            if let albums = cache.albums {
                if albums.isEmpty {
                    MusicEmptyNote(title: L("보관함에 음악이 없습니다"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(albums.enumerated()), id: \.offset) { _, album in
                                NavigationLink(value: MusicRoute.album(album)) {
                                    MusicArtworkRow(item: album.representativeItem,
                                                    title: album.representativeItem?.albumTitle ?? L("알 수 없는 앨범"),
                                                    subtitle: album.representativeItem?.albumArtist
                                                        ?? album.representativeItem?.artist ?? "",
                                                    chevron: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                MusicLoading()
            }
        }
        .task { cache.ensure(.albums) }
    }
}

struct MorePage: View {
    let nav: MusicNav

    var body: some View {
        MusicPage(title: L("더 보기"), showsBack: false, nav: nav) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach([MusicGroupKind.genres, .composers, .compilations], id: \.self) { kind in
                        NavigationLink(value: MusicRoute.groups(kind)) {
                            MusicTextRow(title: kind.title, detail: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Detail pages

struct SongListPage: View {
    let title: String
    let items: [MPMediaItem]
    let nav: MusicNav

    var body: some View {
        MusicPage(title: title, showsBack: true, nav: nav) {
            if items.isEmpty {
                MusicEmptyNote(title: L("노래 없음"))
            } else {
                SongList(items: items, nav: nav, showsArtwork: true)
            }
        }
    }
}

struct ArtistPage: View {
    let collection: MPMediaItemCollection
    let nav: MusicNav

    private var artistName: String { collection.representativeItem?.artist ?? L("알 수 없는 아티스트") }

    /// The artist's songs grouped by album, in library order.
    private var albums: [MPMediaItemCollection] {
        var order: [MPMediaEntityPersistentID] = []
        var groups: [MPMediaEntityPersistentID: [MPMediaItem]] = [:]
        for item in collection.items {
            let key = item.albumPersistentID
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        return order.compactMap { key in groups[key].map { MPMediaItemCollection(items: $0) } }
    }

    var body: some View {
        MusicPage(title: artistName, showsBack: true, nav: nav) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    NavigationLink(value: MusicRoute.songs(title: artistName, collection: collection)) {
                        MusicTextRow(title: L("모든 노래"), detail: LF("%d곡", collection.count))
                    }
                    .buttonStyle(.plain)
                    ForEach(Array(albums.enumerated()), id: \.offset) { _, album in
                        NavigationLink(value: MusicRoute.album(album)) {
                            MusicArtworkRow(item: album.representativeItem,
                                            title: album.representativeItem?.albumTitle ?? L("알 수 없는 앨범"),
                                            subtitle: LF("%d곡", album.count),
                                            chevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct AlbumPage: View {
    let collection: MPMediaItemCollection
    let nav: MusicNav

    var body: some View {
        let first = collection.representativeItem
        let items = collection.items
        let total: TimeInterval = items.reduce(0.0) { $0 + $1.playbackDuration }
        MusicPage(title: first?.albumTitle ?? L("앨범"), showsBack: true, nav: nav) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        MediaArtwork(item: first, side: 88)
                            .overlay(Rectangle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(first?.albumArtist ?? first?.artist ?? "")
                                .font(.retro(15, .bold)).foregroundStyle(.black)
                            Text(first?.albumTitle ?? "")
                                .font(.retro(15)).foregroundStyle(Color(hex: 0x333333))
                            Text(LF("%d곡, %d분", items.count, Int((total / 60).rounded())))
                                .font(.retro(13)).foregroundStyle(Color(hex: 0x7A7A7A))
                        }
                        .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(LinearGradient(colors: [Color(hex: 0xF4F4F4), Color(hex: 0xDADADA)], startPoint: .top, endPoint: .bottom))
                    Rectangle().fill(Color(hex: 0xB0B0B0)).frame(height: 1)
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        Button {
                            nav.play(items, startAt: item)
                        } label: {
                            AlbumTrackRow(number: item.albumTrackNumber > 0 ? item.albumTrackNumber : index + 1,
                                          item: item, striped: index % 2 == 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct GroupListPage: View {
    let kind: MusicGroupKind
    let nav: MusicNav
    @State private var groups: [MPMediaItemCollection]?

    var body: some View {
        MusicPage(title: kind.title, showsBack: true, nav: nav) {
            if let groups {
                if groups.isEmpty {
                    MusicEmptyNote(title: L("항목 없음"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                                NavigationLink(value: route(for: group)) {
                                    MusicArtworkRow(item: group.representativeItem, title: title(for: group),
                                                    subtitle: LF("%d곡", group.count), chevron: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                MusicLoading()
            }
        }
        .task { if groups == nil { groups = MusicLibraryCache.groups(kind) } }
    }

    private func title(for group: MPMediaItemCollection) -> String {
        let item = group.representativeItem
        switch kind {
        case .genres: return item?.genre ?? L("알 수 없음")
        case .composers: return item?.composer ?? L("알 수 없음")
        case .compilations: return item?.albumTitle ?? L("알 수 없는 앨범")
        }
    }

    private func route(for group: MPMediaItemCollection) -> MusicRoute {
        kind == .compilations ? .album(group) : .songs(title: title(for: group), collection: group)
    }
}

// MARK: - Rows

struct SongList: View {
    let items: [MPMediaItem]
    let nav: MusicNav
    var showsArtwork: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Button { nav.play(items, shuffle: true) } label: {
                    HStack {
                        Text(L("셔플")).font(.retro(20, .bold)).foregroundStyle(.black)
                        Spacer()
                        Image(systemName: "shuffle").font(.system(size: 18, weight: .bold)).foregroundStyle(Color(hex: 0x3A5FA8))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color.white)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xE0E0E0)).frame(height: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button { nav.play(items, startAt: item) } label: {
                        MusicArtworkRow(item: showsArtwork ? item : nil,
                                        title: item.title ?? L("알 수 없는 노래"),
                                        subtitle: [item.artist, item.albumTitle].compactMap { $0 }.joined(separator: " — "),
                                        chevron: false,
                                        showsArtwork: showsArtwork,
                                        isCurrent: MusicService.shared.nowPlaying?.persistentID == item.persistentID)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct MusicTextRow: View {
    var title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.retro(20, .bold)).foregroundStyle(.black).lineLimit(1)
            Spacer(minLength: 8)
            if let detail {
                Text(detail).font(.retro(15)).foregroundStyle(Color(hex: 0x8A8A8A))
            }
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: 0x7F7F7F))
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xE0E0E0)).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

struct MusicArtworkRow: View {
    var item: MPMediaItem?
    var title: String
    var subtitle: String
    var chevron: Bool
    var showsArtwork: Bool = true
    var isCurrent: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            if showsArtwork {
                MediaArtwork(item: item, side: 44)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if isCurrent {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 11)).foregroundStyle(Color(hex: 0x3A6FD8))
                    }
                    Text(title).font(.retro(17, .bold)).foregroundStyle(.black).lineLimit(1)
                }
                if !subtitle.isEmpty {
                    Text(subtitle).font(.retro(13)).foregroundStyle(Color(hex: 0x7A7A7A)).lineLimit(1)
                }
            }
            .padding(.leading, showsArtwork ? 0 : 12)
            Spacer(minLength: 8)
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: 0x7F7F7F))
                    .padding(.trailing, 12)
            }
        }
        .frame(height: 44)
        .background(Color.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xE0E0E0)).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

struct AlbumTrackRow: View {
    var number: Int
    var item: MPMediaItem
    var striped: Bool

    var body: some View {
        let isCurrent = MusicService.shared.nowPlaying?.persistentID == item.persistentID
        HStack(spacing: 8) {
            Group {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 12)).foregroundStyle(Color(hex: 0x3A6FD8))
                } else {
                    Text("\(number)").font(.retro(15, .bold)).foregroundStyle(Color(hex: 0x6A6A6A))
                }
            }
            .frame(width: 28, alignment: .trailing)
            Text(item.title ?? L("알 수 없는 노래")).font(.retro(15, .bold)).foregroundStyle(.black).lineLimit(1)
            Spacer(minLength: 8)
            Text(MediaFormat.duration(item.playbackDuration)).font(.retro(14)).foregroundStyle(Color(hex: 0x6A6A6A))
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(striped ? Color(hex: 0xF0F0F0) : Color.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xDADADA)).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

struct MediaArtwork: View {
    var item: MPMediaItem?
    var side: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let image = item?.artwork?.image(at: CGSize(width: side * displayScale, height: side * displayScale))
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: 0x9A9A9A), Color(hex: 0x5A5A5A)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.45, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .accessibilityHidden(true)
    }
}

struct MusicLoading: View {
    var body: some View {
        Text(L("불러오는 중…"))
            .font(.retro(17))
            .foregroundStyle(Color(hex: 0x8A8A8A))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown when MediaPlayer exposes nothing: explains what this player can and cannot browse.
struct MusicEmptyNote: View {
    var title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Color(hex: 0xB0B0B0))
            Text(title)
                .font(.retro(20, .bold))
                .foregroundStyle(Color(hex: 0x6A6A6A))
            Text(L("Apple Music 스트리밍 카탈로그는 여기에서 탐색할 수 없습니다. 보관함에 추가하거나 다운로드한 항목은 시스템 음악 플레이어로 재생됩니다."))
                .font(.retro(14))
                .foregroundStyle(Color(hex: 0x8A8A8A))
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Chrome

/// iOS 4 "Now Playing" bar button: a right-pointing arrow-shaped button with two-line text.
struct NowPlayingBarButton: View {
    @Environment(\.retroTheme) private var theme
    var action: () -> Void

    var body: some View {
        Button {
            SoundService.shared.play(.tock)
            action()
        } label: {
            Text(L("지금\n재생 중"))
                .font(.retroFixed(10, .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 0, y: -1)
                .padding(.leading, 8)
                .padding(.trailing, 16)
                .frame(minHeight: 30)
                .background(
                    BackButtonShape()
                        .fill(LinearGradient(colors: [theme.barButtonTop, theme.barButtonBottom], startPoint: .top, endPoint: .bottom))
                        .overlay(BackButtonShape().stroke(Color.black.opacity(0.5), lineWidth: 1))
                        .scaleEffect(x: -1, y: 1)
                        .shadow(color: .white.opacity(0.35), radius: 0, y: 1)
                )
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(L("지금 재생 중"))
    }
}

/// Black glossy iPod tab bar.
struct IPodTabBar: View {
    @Binding var selection: IPodTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(IPodTab.allCases) { tab in
                let selected = tab == selection
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    selection = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(selected
                                             ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xD6EEFF), Color(hex: 0x2F8CFF)],
                                                                            startPoint: .top, endPoint: .bottom))
                                             : AnyShapeStyle(Color(hex: 0x8C8C8C)))
                            .frame(height: 26)
                        Text(tab.title)
                            .font(.retroFixed(10, .bold))
                            .foregroundStyle(selected ? Color.white : Color(hex: 0x9C9C9C))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 45)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.15))
                                .padding(.vertical, 2)
                                .padding(.horizontal, 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 49)
        .background(
            LinearGradient(stops: [
                .init(color: Color(hex: 0x3C3C3C), location: 0),
                .init(color: Color(hex: 0x1E1E1E), location: 0.5),
                .init(color: Color(hex: 0x080808), location: 0.5),
                .init(color: Color.black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0x5A5A5A)).frame(height: 1) }
    }
}
