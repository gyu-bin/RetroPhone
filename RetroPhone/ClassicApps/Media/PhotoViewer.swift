import CoreTransferable
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PhotoViewerContext: Identifiable {
    let id = UUID()
    let assets: PHFetchResult<PHAsset>
    let startIndex: Int
    let albumTitle: String
}

/// Full-screen iOS 4 photo viewer: black translucent bars, paging, tap to toggle bars,
/// pinch / double-tap zoom, share and "use as wallpaper".
struct PhotoViewer: View {
    let context: PhotoViewerContext
    @Binding var barsVisible: Bool
    var onClose: () -> Void

    @State private var index: Int?
    @State private var zoomed = false
    @State private var showWallpaperSheet = false
    @State private var wallpaperDone = false
    @State private var wallpaperFailed = false
    @State private var working = false
    @State private var shareThumbnail: UIImage?
    @Environment(\.deviceInsets) private var insets
    /// Non-zero when the classic bezel is on: the app area already sits between status bar and chin.
    @Environment(\.bezelPadding) private var bezelPadding

    init(context: PhotoViewerContext, barsVisible: Binding<Bool>, onClose: @escaping () -> Void) {
        self.context = context
        self._barsVisible = barsVisible
        self.onClose = onClose
        self._index = State(initialValue: context.startIndex)
    }

    private var count: Int { context.assets.count }
    private var currentIndex: Int { min(max(0, index ?? context.startIndex), max(0, count - 1)) }
    private var currentAsset: PHAsset? { count > 0 ? context.assets.object(at: currentIndex) : nil }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                pager(size: geo.size)
                if barsVisible {
                    bars
                        .transition(.opacity)
                }
                if working {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .padding(24)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.6)))
                }
            }
        }
        .ignoresSafeArea()
        .task(id: currentIndex) { await loadShareThumbnail() }
        .retroActionSheet(nil, isPresented: $showWallpaperSheet, buttons: [
            RetroSheetButton(title: L("잠금 화면으로 설정")) { setWallpaper(lock: true, home: false) },
            RetroSheetButton(title: L("홈 화면으로 설정")) { setWallpaper(lock: false, home: true) },
            RetroSheetButton(title: L("둘 다 설정")) { setWallpaper(lock: true, home: true) },
            RetroSheetButton(title: L("취소"), role: .cancel),
        ])
        .retroAlert(L("배경화면이 설정되었습니다"), isPresented: $wallpaperDone)
        .retroAlert(L("배경화면을 설정할 수 없음"), isPresented: $wallpaperFailed,
                    message: L("사진을 불러오지 못했습니다."))
    }

    private func pager(size: CGSize) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    ZoomablePhotoPage(asset: context.assets.object(at: i), size: size,
                                      onTap: toggleBars,
                                      onZoomChange: { isZoomed in
                                          if i == currentIndex { zoomed = isZoomed }
                                      })
                        .frame(width: size.width, height: size.height)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $index)
        .scrollIndicators(.hidden)
        .scrollDisabled(zoomed)
        .onChange(of: index) { zoomed = false }
    }

    private var bars: some View {
        VStack(spacing: 0) {
            // The root draws the translucent status bar in this band.
            Color.clear.frame(height: bezelPadding.top > 0 ? 0 : max(20, insets.top))
            ClassicNavBar(title: LF("%d/%d", currentIndex + 1, count), style: .blackTranslucent,
                          leading: {
                              ClassicBarButton(title: context.albumTitle, kind: .back, barStyle: .blackTranslucent) { onClose() }
                          },
                          trailing: { EmptyView() })
            Spacer()
            ClassicToolbar(style: .blackTranslucent) {
                if let asset = currentAsset {
                    ShareLink(item: SharedPhoto(localIdentifier: asset.localIdentifier),
                              preview: SharePreview(L("사진"), image: Image(uiImage: shareThumbnail ?? UIImage()))) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 0, y: -1)
                            .frame(width: 44, height: 40)
                    }
                    .accessibilityLabel(L("공유"))
                }
                Spacer()
                ToolbarIconButton(systemImage: "photo.on.rectangle", label: L("배경화면으로 사용"),
                                  enabled: currentAsset != nil && !working) {
                    showWallpaperSheet = true
                }
            }
            Color.black.opacity(0.5).frame(height: bezelPadding.bottom > 0 ? 0 : insets.bottom)
        }
    }

    private func toggleBars() {
        withAnimation(.easeInOut(duration: 0.25)) { barsVisible.toggle() }
    }

    private func loadShareThumbnail() async {
        guard let asset = currentAsset else { return }
        shareThumbnail = await PhotoLibraryService.shared.image(for: asset, size: CGSize(width: 240, height: 240))
    }

    private func setWallpaper(lock: Bool, home: Bool) {
        guard let asset = currentAsset, !working else { return }
        working = true
        Task {
            defer { working = false }
            guard let image = await PhotoLoading.image(for: asset, maxPixel: 2400),
                  let file = FileStore.saveImage(image, maxDimension: 2400) else {
                wallpaperFailed = true
                return
            }
            let store = SettingsStore.shared
            let old = [store.value.lockWallpaper, store.value.homeWallpaper]
            var value = store.value
            if lock { value.lockWallpaper = .custom(file: file) }
            if home { value.homeWallpaper = .custom(file: file) }
            store.value = value
            // Remove custom wallpaper files that are no longer referenced (same policy as Settings).
            for case .custom(let previous) in old
            where value.lockWallpaper != .custom(file: previous) && value.homeWallpaper != .custom(file: previous) {
                FileStore.deleteImage(previous)
            }
            Haptics.success()
            wallpaperDone = true
        }
    }
}

// MARK: - Page

struct ZoomablePhotoPage: View {
    let asset: PHAsset
    let size: CGSize
    var onTap: () -> Void
    var onZoomChange: (Bool) -> Void

    @State private var loader = AssetImageLoader()
    @State private var wantsDetail = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZoomImageView(image: loader.image, onSingleTap: onTap) { isZoomed in
            onZoomChange(isZoomed)
            if isZoomed && !wantsDetail {
                wantsDetail = true
                load()
            }
        }
        .onAppear { load() }
        .onDisappear { loader.cancel() }
        .accessibilityElement()
        .accessibilityLabel(L("사진"))
        .accessibilityAddTraits(.isImage)
    }

    /// Screen-sized image first; a sharper one only once the user zooms in.
    private func load() {
        let factor: CGFloat = wantsDetail ? 2.5 : 1
        let target = CGSize(width: min(4096, size.width * displayScale * factor),
                            height: min(4096, size.height * displayScale * factor))
        loader.load(asset, targetSize: target, contentMode: .aspectFit, options: PhotoRequestOptions.fullScreen)
    }
}

struct ZoomImageView: UIViewRepresentable {
    var image: UIImage?
    var onSingleTap: () -> Void
    var onZoomChange: (Bool) -> Void

    func makeUIView(context: Context) -> ZoomingScrollView {
        ZoomingScrollView(frame: .zero)
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        view.onSingleTap = onSingleTap
        view.onZoomChange = onZoomChange
        view.display(image)
    }
}

/// UIScrollView-based zooming (pinch, double tap) with the image centred at every scale.
final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    var onSingleTap: (() -> Void)?
    var onZoomChange: ((Bool) -> Void)?
    private var reportedZoomed = false
    private var lastBoundsSize: CGSize = .zero
    private var imageSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
        // Unzoomed, a horizontal swipe must reach the pager (next / previous photo), not this view.
        panGestureRecognizer.isEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func display(_ image: UIImage?) {
        guard imageView.image !== image else { return }
        let newSize = image?.size ?? .zero
        let aspectChanged = !Self.sameAspect(newSize, imageSize)
        imageView.image = image
        imageSize = newSize
        if aspectChanged { layoutImage() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            layoutImage()
        }
    }

    private static func sameAspect(_ a: CGSize, _ b: CGSize) -> Bool {
        guard a.width > 0, a.height > 0, b.width > 0, b.height > 0 else { return false }
        return abs(a.width / a.height - b.width / b.height) < 0.01
    }

    private func layoutImage() {
        zoomScale = 1
        panGestureRecognizer.isEnabled = false
        let available = bounds.size
        guard available.width > 0, available.height > 0 else { return }
        var fitted = available
        if imageSize.width > 0, imageSize.height > 0 {
            let fit = min(available.width / imageSize.width, available.height / imageSize.height)
            fitted = CGSize(width: (imageSize.width * fit).rounded(), height: (imageSize.height * fit).rounded())
        }
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
        centerImage()
    }

    private func centerImage() {
        let size = imageView.frame.size
        let x = max(0, (bounds.width - size.width) / 2)
        let y = max(0, (bounds.height - size.height) / 2)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        let isZoomed = zoomScale > minimumZoomScale + 0.01
        panGestureRecognizer.isEnabled = isZoomed
        guard isZoomed != reportedZoomed else { return }
        reportedZoomed = isZoomed
        let callback = onZoomChange
        // Report asynchronously: zoom can change during a SwiftUI update pass.
        Task { @MainActor in callback?(isZoomed) }
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }
}

// MARK: - Loading / sharing helpers (nonisolated: closures here may run off the main thread)

nonisolated enum PhotoLoading {
    /// High-quality image no larger than `maxPixel` on its long side.
    static func image(for asset: PHAsset, maxPixel: CGFloat) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset,
                                                  targetSize: CGSize(width: maxPixel, height: maxPixel),
                                                  contentMode: .aspectFit,
                                                  options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Original photo data as JPEG (re-encoded from HEIC if needed, metadata kept).
    static func jpegData(localIdentifier: String) async throws -> Data {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            throw CocoaError(.fileNoSuchFile)
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        let result: (Data?, String?) = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                continuation.resume(returning: (data, uti))
            }
        }
        guard let data = result.0 else { throw CocoaError(.fileReadUnknown) }
        if let uti = result.1, let type = UTType(uti), type.conforms(to: .jpeg) { return data }
        guard let jpeg = RetroPhotoProcessor.jpeg(from: data) else { throw CocoaError(.fileReadCorruptFile) }
        return jpeg
    }
}

/// Lazily exported photo for ShareLink: the full-quality data is only loaded when the user
/// actually picks a share destination.
nonisolated struct SharedPhoto: Transferable {
    let localIdentifier: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { photo in
            try await PhotoLoading.jpegData(localIdentifier: photo.localIdentifier)
        }
    }
}
