import SwiftUI

/// Home-screen geometry derived from the screen size, scaled from the iPhone 4's 320-pt layout.
struct HomeMetrics {
    let size: CGSize
    let insets: EdgeInsets

    var k: CGFloat { min(size.width / 320, 1.35) }
    var iconSize: CGFloat { min(57 * k, 74) }
    var cellWidth: CGFloat { size.width / CGFloat(HomeLayout.columns) }
    var gridTop: CGFloat { max(insets.top, 20) + 10 }
    var dockHeight: CGFloat { iconSize + 34 * k }
    var dockTop: CGFloat { size.height - max(insets.bottom, 8) - dockHeight }
    var dotsHeight: CGFloat { 22 }
    var gridHeight: CGFloat { max(200, dockTop - dotsHeight - gridTop) }
    var rowHeight: CGFloat { gridHeight / CGFloat(HomeLayout.rows) }
    var labelSize: CGFloat { min(11 * k, 13) }

    /// Center of a placement in home coordinates.
    func center(of p: Placement) -> CGPoint {
        CGPoint(x: (CGFloat(p.column) + CGFloat(p.columns) / 2) * cellWidth,
                y: gridTop + (CGFloat(p.row) + CGFloat(p.rows) / 2) * rowHeight)
    }

    func frameSize(of p: Placement) -> CGSize {
        CGSize(width: CGFloat(p.columns) * cellWidth, height: CGFloat(p.rows) * rowHeight)
    }

    /// Widget content size (inset from its cells so it lines up with icon edges).
    func widgetSize(_ size: WidgetSize) -> CGSize {
        let inset = (cellWidth - iconSize) / 2
        return CGSize(width: CGFloat(size.columns) * cellWidth - inset * 2,
                      height: CGFloat(size.rows) * rowHeight - rowHeight * 0.18)
    }

    func cell(at point: CGPoint) -> (column: Int, row: Int) {
        let col = Int(point.x / cellWidth)
        let row = Int((point.y - gridTop) / rowHeight)
        return (max(0, min(HomeLayout.columns - 1, col)), max(0, min(HomeLayout.rows - 1, row)))
    }

    func isInDock(_ point: CGPoint) -> Bool { point.y >= dockTop - 6 }

    func dockSlotCenters(count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        let spacing = size.width / CGFloat(max(count, 1))
        let y = dockTop + dockHeight * 0.42
        return (0..<count).map { CGPoint(x: spacing * (CGFloat($0) + 0.5), y: y) }
    }

    func dockIndex(for x: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let spacing = size.width / CGFloat(count)
        return max(0, min(count - 1, Int(x / spacing)))
    }

    /// Reading-order insertion index for a point, given items laid out on a page.
    static func insertionIndex(for cell: (column: Int, row: Int), placements: [Placement]) -> Int {
        let target = cell.row * HomeLayout.columns + cell.column
        for p in placements where !p.overflow {
            let origin = p.row * HomeLayout.columns + p.column
            // Inside a multi-cell item → insert before it.
            if cell.row >= p.row && cell.row < p.row + p.rows && cell.column >= p.column && cell.column < p.column + p.columns {
                return p.index
            }
            if origin >= target { return p.index }
        }
        return placements.filter { !$0.overflow }.count
    }
}
