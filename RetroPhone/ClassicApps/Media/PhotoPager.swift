import Photos
import SwiftUI
import UIKit

/// Horizontal photo paging built on UIPageViewController, the same structure as the system Photos
/// app: each page is a UIKit zoom scroll view, so paging and zooming share touches the UIKit way.
/// (A SwiftUI paging ScrollView around UIKit zoom views didn't page on device.)
struct PhotoPager: UIViewControllerRepresentable {
    let assets: PHFetchResult<PHAsset>
    @Binding var index: Int?
    let startIndex: Int
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal,
                                         options: [.interPageSpacing: 24])
        pager.view.backgroundColor = .clear
        pager.dataSource = context.coordinator
        pager.delegate = context.coordinator
        if let first = context.coordinator.page(at: startIndex) {
            pager.setViewControllers([first], direction: .forward, animated: false)
        }
        return pager
    }

    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PhotoPager
        init(_ parent: PhotoPager) { self.parent = parent }

        func page(at i: Int) -> PhotoPageViewController? {
            guard i >= 0, i < parent.assets.count else { return nil }
            let page = PhotoPageViewController(index: i, asset: parent.assets.object(at: i))
            page.onTap = { [weak self] in self?.parent.onTap() }
            return page
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            (vc as? PhotoPageViewController).flatMap { page(at: $0.index - 1) }
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            (vc as? PhotoPageViewController).flatMap { page(at: $0.index + 1) }
        }

        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let current = pvc.viewControllers?.first as? PhotoPageViewController else { return }
            parent.index = current.index
        }
    }
}

/// One photo: a zoom scroll view showing a screen-sized image, sharpened once the user zooms in.
final class PhotoPageViewController: UIViewController {
    let index: Int
    let asset: PHAsset
    var onTap: (() -> Void)?
    private let zoomView = ZoomingScrollView(frame: .zero)
    private var requestID: PHImageRequestID?
    private var loadedFactor: CGFloat = 0

    init(index: Int, asset: PHAsset) {
        self.index = index
        self.asset = asset
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        zoomView.frame = view.bounds
        zoomView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        zoomView.onSingleTap = { [weak self] in self?.onTap?() }
        zoomView.onZoomChange = { [weak self] zoomed in if zoomed { self?.load(factor: 2.5) } }
        view.addSubview(zoomView)
        view.isAccessibilityElement = true
        view.accessibilityLabel = L("사진")
        view.accessibilityTraits = .image
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if loadedFactor == 0, view.bounds.width > 0 { load(factor: 1) }
    }

    deinit {
        if let requestID { PhotoLibraryService.shared.imageManager.cancelImageRequest(requestID) }
    }

    private func load(factor: CGFloat) {
        guard factor > loadedFactor else { return }
        loadedFactor = factor
        let scale = view.window?.screen.scale ?? 3
        let target = CGSize(width: min(4096, view.bounds.width * scale * factor),
                            height: min(4096, view.bounds.height * scale * factor))
        if let requestID { PhotoLibraryService.shared.imageManager.cancelImageRequest(requestID) }
        requestID = PhotoLibraryService.shared.imageManager.requestImage(
            for: asset, targetSize: target, contentMode: .aspectFit, options: PhotoRequestOptions.fullScreen
        ) { [weak self] image, _ in
            guard let image else { return }
            Task { @MainActor in self?.zoomView.display(image) }
        }
    }
}
