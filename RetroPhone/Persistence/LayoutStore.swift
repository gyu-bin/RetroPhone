import Foundation
import Observation
import UIKit

/// Owns the persisted home layout. Saves are debounced so drag operations don't thrash the disk.
@Observable
final class LayoutStore {
    static let shared = LayoutStore()
    static let fileName = "layout.json"

    private let persist: Bool
    private var saveTask: Task<Void, Never>?

    var layout: HomeLayout {
        didSet { if layout != oldValue { scheduleSave() } }
    }

    init(persist: Bool = true, layout: HomeLayout? = nil) {
        self.persist = persist
        self.layout = layout ?? (persist ? FileStore.load(HomeLayout.self, from: Self.fileName) : nil) ?? .default
    }

    func update(_ change: (inout HomeLayout) -> Void) {
        var copy = layout
        change(&copy)
        layout = copy
    }

    private func scheduleSave() {
        guard persist else { return }
        saveTask?.cancel()
        let snapshot = layout
        saveTask = Task { [snapshot] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            FileStore.save(snapshot, to: Self.fileName)
        }
    }

    /// Writes immediately (called when the app goes to background).
    func flush() {
        guard persist else { return }
        saveTask?.cancel()
        FileStore.save(layout, to: Self.fileName)
    }

    // MARK: Display helpers

    func name(for app: AppID) -> String {
        if let custom = layout.overrides[app.raw]?.name, !custom.isEmpty { return custom }
        return AppCatalog.defaultName(app, custom: layout.customApps)
    }

    func art(for app: AppID) -> IconArt {
        layout.overrides[app.raw]?.art ?? AppCatalog.defaultArt(app, custom: layout.customApps)
    }

    func customIcon(for app: AppID) -> UIImage? {
        guard let file = layout.overrides[app.raw]?.customIconFile else { return nil }
        return FileStore.loadImage(file)
    }

    func external(_ app: AppID) -> ExternalApp? { AppCatalog.external(app, custom: layout.customApps) }

    func setOverride(_ app: AppID, _ change: (inout AppOverride) -> Void) {
        update { l in
            var o = l.overrides[app.raw] ?? AppOverride()
            change(&o)
            l.overrides[app.raw] = (o == AppOverride()) ? nil : o
        }
    }

    // MARK: Backup / restore

    struct Backup: Codable {
        var format = "RetroPhoneBackup"
        var version = 1
        var createdAt = Date()
        var layout: HomeLayout
        var settings: RetroSettings
    }

    func exportBackup(settings: RetroSettings) throws -> URL {
        let backup = Backup(layout: layout, settings: settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RetroPhone-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func decodeBackup(_ data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)
        guard backup.format == "RetroPhoneBackup" else { throw CocoaError(.fileReadCorruptFile) }
        return backup
    }
}
