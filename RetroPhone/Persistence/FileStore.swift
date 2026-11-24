import Foundation
import UIKit
import os

/// Local-only JSON + image persistence in Application Support. Nothing leaves the device.
enum FileStore {
    private static let log = Logger(subsystem: "RetroPhone", category: "FileStore")

    static var baseURL: URL = {
        let fm = FileManager.default
        let url = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                               appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let dir = url.appendingPathComponent("RetroPhone", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var imagesURL: URL {
        let dir = baseURL.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(_ name: String) -> URL { baseURL.appendingPathComponent(name) }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = url(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch {
            // Corrupt file: keep a copy for diagnosis, fall back to defaults.
            log.error("Decode failed for \(name, privacy: .public)")
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("corrupt"))
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: url(name), options: [.atomic, .completeFileProtection])
        } catch {
            log.error("Save failed for \(name, privacy: .public)")
        }
    }

    // MARK: Images (custom icons / wallpapers)

    /// Stores a downscaled JPEG/PNG and returns its file name.
    @discardableResult
    static func saveImage(_ image: UIImage, maxDimension: CGFloat, name: String = UUID().uuidString) -> String? {
        let scaled = image.downscaled(maxDimension: maxDimension)
        // Small images (icons) keep PNG for crisp edges/transparency; photos (wallpapers) use JPEG.
        let usePNG = maxDimension <= 600
        guard let data = usePNG ? scaled.pngData() : scaled.jpegData(compressionQuality: 0.88) else { return nil }
        let file = name + (usePNG ? ".png" : ".jpg")
        do {
            try data.write(to: imagesURL.appendingPathComponent(file), options: [.atomic, .completeFileProtection])
            ImageCache.shared.remove(file)
            return file
        } catch { return nil }
    }

    static func loadImage(_ file: String) -> UIImage? {
        if let cached = ImageCache.shared.get(file) { return cached }
        guard let image = UIImage(contentsOfFile: imagesURL.appendingPathComponent(file).path) else { return nil }
        ImageCache.shared.set(file, image)
        return image
    }

    static func deleteImage(_ file: String) {
        ImageCache.shared.remove(file)
        try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(file))
    }
}

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    init() { cache.totalCostLimit = 48 * 1024 * 1024 }
    func get(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func set(_ key: String, _ image: UIImage) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    func remove(_ key: String) { cache.removeObject(forKey: key as NSString) }
}

extension UIImage {
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let ratio = maxDimension / longest
        let target = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
