import SwiftUI
import Observation

/// Live drag-and-drop state for home-screen editing.
@Observable
final class HomeDragController {
    enum Source: Equatable {
        case page(UUID)
        case dock(AppID)
    }

    private(set) var source: Source?
    private(set) var item: HomeItem?
    var location: CGPoint = .zero
    /// Insertion index on the current page (in the list that excludes the dragged item).
    var targetIndex: Int?
    var dockIndex: Int?
    var folderTarget: UUID?
    private(set) var overDock = false
    private var hoverCandidate: UUID?
    private var hoverSince = Date.distantPast
    private var edgeTask: Task<Void, Never>?
    private var edgeDirection = 0

    var isActive: Bool { source != nil }
    var draggedPageID: UUID? { if case .page(let id) = source { return id }; return nil }
    var draggedDockApp: AppID? { if case .dock(let a) = source { return a }; return nil }

    func begin(_ source: Source, item: HomeItem, at point: CGPoint) {
        self.source = source
        self.item = item
        location = point
        Haptics.tap(.medium)
    }

    func reset() {
        source = nil
        item = nil
        targetIndex = nil
        dockIndex = nil
        overDock = false
        folderTarget = nil
        hoverCandidate = nil
        edgeTask?.cancel()
        edgeTask = nil
        edgeDirection = 0
    }

    /// Updates targets for a new finger position.
    func update(to point: CGPoint, metrics: HomeMetrics, pageItems: [HomeItem], dockCount: Int,
                flipPage: @escaping (Int) -> Void) {
        location = point
        guard let item else { return }

        overDock = metrics.isInDock(point)
        if overDock {
            folderTarget = nil
            hoverCandidate = nil
            let canDock = item.appID != nil && (draggedDockApp != nil || dockCount < HomeLayout.dockCapacity)
            let count = draggedDockApp != nil ? dockCount : dockCount + 1
            dockIndex = canDock ? metrics.dockIndex(for: point.x, count: count) : nil
            cancelEdge()
            return
        }
        dockIndex = nil

        // Edge hold → change page.
        let edge = point.x < 22 ? -1 : (point.x > metrics.size.width - 22 ? 1 : 0)
        if edge != edgeDirection {
            cancelEdge()
            edgeDirection = edge
            if edge != 0 {
                edgeTask = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(650))
                        guard let self, !Task.isCancelled, self.edgeDirection == edge else { return }
                        flipPage(edge)
                    }
                }
            }
        }

        let base = pageItems.filter { $0.id != draggedPageID }
        let placements = HomeLayout.placements(for: base)

        // Folder hover: dragging an app close to another app/folder's icon center.
        if item.appID != nil {
            let radius = min(metrics.cellWidth, metrics.rowHeight) * 0.3
            let hit = zip(base, placements).first { pair in
                guard !pair.1.overflow, pair.0.widget == nil else { return false }
                let c = metrics.center(of: pair.1)
                let iconCenter = CGPoint(x: c.x, y: c.y - metrics.rowHeight * 0.08)
                return hypot(iconCenter.x - point.x, iconCenter.y - point.y) < radius
            }?.0
            if let hit {
                if hoverCandidate != hit.id { hoverCandidate = hit.id; hoverSince = Date() }
                else if Date().timeIntervalSince(hoverSince) > 0.4, folderTarget != hit.id {
                    folderTarget = hit.id
                    Haptics.selection()
                }
                return  // Don't reflow while hovering an icon.
            }
        }
        hoverCandidate = nil
        folderTarget = nil
        let cell = metrics.cell(at: point)
        let newIndex = HomeMetrics.insertionIndex(for: cell, placements: placements)
        if newIndex != targetIndex {
            withAnimation(.easeInOut(duration: 0.22)) { targetIndex = newIndex }
        }
    }

    private func cancelEdge() {
        edgeTask?.cancel()
        edgeTask = nil
        edgeDirection = 0
    }
}
