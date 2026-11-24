import Photos
import PhotosUI
import SwiftUI
import UIKit

// MARK: - Root

struct PhotosAppView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var watcher = PhotoLibraryWatcher()
    @State private var albums: [PhotoAlbum] = []
    @State private var loaded = false
    @State private var viewer: PhotoViewerContext?
    @State private var barsVisible = true

    var body: some View {
        let library = PhotoLibraryService.shared
        ZStack {
            NavigationStack {
                ClassicPage(title: L("앨범"),
                            background: library.canRead ? AnyView(Color.white) : AnyView(PinstripeBackground()),
                            leading: { EmptyView() }, trailing: { EmptyView() }) {
                    if library.canRead {
                        albumList(limited: library.status == .limited)
                    } else if library.isDenied {
                        PermissionPlaceholder(systemImage: "photo.on.rectangle", title: L("사진 접근 권한이 필요합니다"),
                                              message: L("사진을 보려면 iOS 설정에서 사진 접근을 허용하세요."), denied: true)
                    } else {
                        PermissionPlaceholder(systemImage: "photo.on.rectangle", title: L("사진"),
                                              message: L("사진 보관함의 사진을 보려면 접근을 허용하세요."),
                                              requestTitle: L("접근 허용"),
                                              request: { Task { await requestAccess() } })
                    }
                }
                .navigationDestination(for: PhotoAlbum.self) { album in
                    PhotoGridView(album: album, revision: watcher.revision) { assets, index in
                        barsVisible = true
                        withAnimation(.easeOut(duration: 0.25)) {
                            viewer = PhotoViewerContext(assets: assets, startIndex: index, albumTitle: album.title)
                        }
                    }
                }
            }
            if let viewer {
                PhotoViewer(context: viewer, barsVisible: $barsVisible) {
                    withAnimation(.easeOut(duration: 0.25)) { self.viewer = nil }
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .preference(key: StatusBarStyleKey.self, value: viewer != nil ? StatusBarStyle.translucent : nil)
        .retroStatusBarHidden(viewer != nil && !barsVisible)
        .task { await requestAccess() }
        .onChange(of: watcher.revision) { reload() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            library.refreshStatus()
            if library.canRead { watcher.start(); reload() }
        }
        .onDisappear { watcher.stop() }
    }

    @ViewBuilder
    private func albumList(limited: Bool) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        PhotoAlbumRow(album: album)
                    }
                    .buttonStyle(.plain)
                }
                if loaded && albums.isEmpty {
                    Text(L("사진 없음"))
                        .font(.retro(20, .bold))
                        .foregroundStyle(Color(hex: 0x9A9A9A))
                        .padding(.top, 60)
                }
                if limited {
                    VStack(spacing: 10) {
                        Text(L("선택한 사진에만 접근할 수 있습니다."))
                            .font(.retro(14))
                            .foregroundStyle(Color(hex: 0x6A6A6A))
                            .multilineTextAlignment(.center)
                        GlossyButton(title: L("사진 선택 변경"), tint: .gray, height: 36) { presentLimitedPicker() }
                            .frame(maxWidth: 220)
                    }
                    .padding(20)
                }
            }
        }
    }

    private func requestAccess() async {
        let library = PhotoLibraryService.shared
        if !library.canRead && !library.isDenied { await library.requestAccess() }
        library.refreshStatus()
        guard library.canRead else { return }
        watcher.start()
        reload()
    }

    private func reload() {
        guard PhotoLibraryService.shared.canRead else { return }
        albums = PhotoAlbumLoader.albums()
        loaded = true
    }

    /// Lets a user who granted limited access change the selection (public PhotoKit API).
    private func presentLimitedPicker() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              var controller = scene.keyWindow?.rootViewController else { return }
        while let presented = controller.presentedViewController { controller = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }
}

// MARK: - Albums

struct PhotoAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let collection: PHAssetCollection
    let count: Int
    let keyAsset: PHAsset?
}

enum PhotoAlbumLoader {
    /// Images only, oldest first (iOS 4 grids start at the top with the oldest photo).
    static func imageOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return options
    }

    static func albums() -> [PhotoAlbum] {
        PhotoLibraryService.shared.albums().compactMap { collection in
            let assets = PHAsset.fetchAssets(in: collection, options: imageOptions())
            let isLibrary = collection.assetCollectionSubtype == .smartAlbumUserLibrary
            if !isLibrary && assets.count == 0 { return nil }
            return PhotoAlbum(id: collection.localIdentifier,
                              title: isLibrary ? L("카메라 롤") : (collection.localizedTitle ?? L("앨범")),
                              collection: collection,
                              count: assets.count,
                              keyAsset: assets.lastObject)
        }
    }

    static func assets(in album: PhotoAlbum) -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(in: album.collection, options: imageOptions())
    }
}

struct PhotoAlbumRow: View {
    let album: PhotoAlbum
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Group {
                    if let asset = album.keyAsset {
                        PhotoThumbnailCell(asset: asset, side: 57,
                                           pixelSize: CGSize(width: 57 * displayScale, height: 57 * displayScale))
                    } else {
                        Color(hex: 0xE6E6E6).frame(width: 57, height: 57)
                    }
                }
                HStack(spacing: 6) {
                    Text(album.title)
                        .font(.retro(20, .bold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                    Text("(\(album.count))")
                        .font(.retro(20))
                        .foregroundStyle(Color(hex: 0x8A8A8A))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x7F7F7F))
                    .padding(.trailing, 10)
            }
            .frame(height: 57)
            Rectangle().fill(Color(hex: 0xE0E0E0)).frame(height: 1)
        }
        .background(Color.white)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.title), \(LF("사진 %d장", album.count))")
    }
}

// MARK: - Grid

struct PhotoGridView: View {
    let album: PhotoAlbum
    let revision: Int
    var onOpen: (PHFetchResult<PHAsset>, Int) -> Void

    @State private var assets: PHFetchResult<PHAsset>?
    @State private var prefetcher = ThumbnailPrefetcher()
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ClassicPage(title: album.title, background: AnyView(Color.white),
                    leading: { ClassicBackButton(title: L("앨범")) }, trailing: { EmptyView() }) {
            GeometryReader { geo in
                let spacing: CGFloat = 4
                let side = max(1, floor((geo.size.width - spacing * 5) / 4))
                let pixel = CGSize(width: side * displayScale, height: side * displayScale)
                if let assets, assets.count > 0 {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: spacing), count: 4),
                                  spacing: spacing) {
                            ForEach(0..<assets.count, id: \.self) { index in
                                PhotoThumbnailCell(asset: assets.object(at: index), side: side, pixelSize: pixel)
                                    .onTapGesture {
                                        SoundService.shared.play(.tock)
                                        onOpen(assets, index)
                                    }
                                    .onAppear { prefetcher.visible(index, in: assets, size: pixel) }
                            }
                        }
                        .padding(spacing)
                        Text(LF("사진 %d장", assets.count))
                            .font(.retro(17))
                            .foregroundStyle(Color(hex: 0x808080))
                            .padding(.top, 10)
                            .padding(.bottom, 18)
                    }
                    .defaultScrollAnchor(.bottom)
                } else if assets != nil {
                    Text(L("사진 없음"))
                        .font(.retro(20, .bold))
                        .foregroundStyle(Color(hex: 0x9A9A9A))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: revision) { assets = PhotoAlbumLoader.assets(in: album) }
        .onDisappear { prefetcher.stopAll() }
    }
}

// MARK: - Thumbnails

enum PhotoRequestOptions {
    /// Shared by grid requests and PHCachingImageManager pre-caching so cache hits line up.
    static let thumbnail: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }()

    static let fullScreen: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }()
}

/// Cancellable PHCachingImageManager request bound to one view.
@Observable
final class AssetImageLoader {
    private(set) var image: UIImage?
    @ObservationIgnored private var requestID: PHImageRequestID?
    @ObservationIgnored private var key: String?

    func load(_ asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode, options: PHImageRequestOptions) {
        let newKey = "\(asset.localIdentifier)|\(Int(targetSize.width))x\(Int(targetSize.height))"
        guard newKey != key else { return }
        cancel()
        key = newKey
        let manager = PhotoLibraryService.shared.imageManager
        requestID = manager.requestImage(for: asset, targetSize: targetSize, contentMode: contentMode,
                                         options: options) { [weak self] result, _ in
            guard let result else { return }
            Task { @MainActor in
                guard let self, self.key == newKey else { return }
                self.image = result
            }
        }
    }

    func cancel() {
        if let requestID { PhotoLibraryService.shared.imageManager.cancelImageRequest(requestID) }
        requestID = nil
        key = nil
    }
}

/// Starts/stops PHCachingImageManager caching for a window around the visible grid cells.
final class ThumbnailPrefetcher {
    private var assets: PHFetchResult<PHAsset>?
    private var size: CGSize = .zero
    private var cached: Range<Int> = 0..<0

    func visible(_ index: Int, in assets: PHFetchResult<PHAsset>, size: CGSize) {
        if assets !== self.assets || size != self.size {
            stopAll()
            self.assets = assets
            self.size = size
        }
        let window = max(0, index - 48)..<min(assets.count, index + 48)
        if !cached.isEmpty && abs(window.lowerBound - cached.lowerBound) < 16 && abs(window.upperBound - cached.upperBound) < 16 {
            return
        }
        let manager = PhotoLibraryService.shared.imageManager
        let added = IndexSet(integersIn: window).subtracting(IndexSet(integersIn: cached))
        let removed = IndexSet(integersIn: cached).subtracting(IndexSet(integersIn: window))
        if !added.isEmpty {
            manager.startCachingImages(for: assets.objects(at: added), targetSize: size,
                                       contentMode: .aspectFill, options: PhotoRequestOptions.thumbnail)
        }
        if !removed.isEmpty {
            manager.stopCachingImages(for: assets.objects(at: removed), targetSize: size,
                                      contentMode: .aspectFill, options: PhotoRequestOptions.thumbnail)
        }
        cached = window
    }

    func stopAll() {
        PhotoLibraryService.shared.imageManager.stopCachingImagesForAllAssets()
        cached = 0..<0
    }
}

struct PhotoThumbnailCell: View {
    let asset: PHAsset
    let side: CGFloat
    let pixelSize: CGSize
    @State private var loader = AssetImageLoader()

    var body: some View {
        ZStack {
            Color(hex: 0xE6E6E6)
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .contentShape(Rectangle())
        .onAppear { load() }
        .onChange(of: asset.localIdentifier) { load() }
        .onDisappear { loader.cancel() }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isImage)
    }

    private func load() {
        loader.load(asset, targetSize: pixelSize, contentMode: .aspectFill, options: PhotoRequestOptions.thumbnail)
    }

    private var accessibilityText: String {
        guard let date = asset.creationDate else { return L("사진") }
        return "\(L("사진")), \(RetroFormat.date(date, template: "yMMMd"))"
    }
}

// MARK: - Library change observation

/// PHPhotoLibraryChangeObserver callbacks arrive on a background queue: this relay is
/// nonisolated and only forwards a Sendable closure.
nonisolated final class PhotoChangeRelay: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}

/// Bumps `revision` (coalesced) whenever the photo library changes.
@Observable
final class PhotoLibraryWatcher {
    private(set) var revision = 0
    @ObservationIgnored private var relay: PhotoChangeRelay?
    @ObservationIgnored private var pending = false

    func start() {
        guard relay == nil, PhotoLibraryService.shared.canRead else { return }
        let relay = PhotoChangeRelay { @Sendable [weak self] in
            Task { @MainActor in self?.scheduleBump() }
        }
        PHPhotoLibrary.shared().register(relay)
        self.relay = relay
    }

    func stop() {
        if let relay { PHPhotoLibrary.shared().unregisterChangeObserver(relay) }
        relay = nil
    }

    private func scheduleBump() {
        guard !pending else { return }
        pending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self else { return }
            self.pending = false
            self.revision += 1
        }
    }
}
