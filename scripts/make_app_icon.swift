// Renders RetroPhone's original app icon (1024×1024) with CoreGraphics.
// Usage: swift scripts/make_app_icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func linear(_ colors: [CGColor], _ from: CGPoint, _ to: CGPoint, _ locs: [CGFloat]? = nil) {
    let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
// CoreGraphics origin is bottom-left.
// Background: deep blue glass
linear([color(0x0B1F3F), color(0x2C5F9E), color(0x7FB2E8)], CGPoint(x: 0, y: 0), CGPoint(x: 0, y: S), [0, 0.6, 1])
// Phone body
let body = CGRect(x: 312, y: 150, width: 400, height: 724)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 70, cornerHeight: 70, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 40, color: color(0x000000, 0.6))
ctx.addPath(bodyPath); ctx.setFillColor(color(0x111111)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState(); ctx.addPath(bodyPath); ctx.clip()
linear([color(0x050505), color(0x3A3A3A)], CGPoint(x: 0, y: body.minY), CGPoint(x: 0, y: body.maxY))
ctx.restoreGState()
ctx.addPath(bodyPath); ctx.setStrokeColor(color(0xC8C8C8)); ctx.setLineWidth(10); ctx.strokePath()
// Screen with a tiny 4×3 icon grid
let screen = CGRect(x: 342, y: 270, width: 340, height: 504)
ctx.saveGState()
ctx.addRect(screen); ctx.clip()
linear([color(0x0E2A3C), color(0x2C6E86)], CGPoint(x: 0, y: screen.minY), CGPoint(x: 0, y: screen.maxY))
let tile: CGFloat = 58, gap: CGFloat = 22
let palette: [UInt32] = [0x5FD24A, 0xFFB24A, 0x5AB2F5, 0xF05A4C, 0xF5DB6A, 0x9AA4AE, 0x8A6CE0, 0x34C3A0, 0xFF7AA8, 0x4A90E2, 0xE8E8E8, 0xFFCC33]
for r in 0..<4 { for c in 0..<4 {
    let x = screen.minX + 22 + CGFloat(c) * (tile + gap)
    let y = screen.maxY - 40 - tile - CGFloat(r) * (tile + gap + 14)
    let rect = CGRect(x: x, y: y, width: tile, height: tile)
    let p = CGPath(roundedRect: rect, cornerWidth: 11, cornerHeight: 11, transform: nil)
    ctx.addPath(p); ctx.setFillColor(color(palette[(r * 4 + c) % palette.count])); ctx.fillPath()
    ctx.saveGState(); ctx.addPath(p); ctx.clip()
    linear([color(0xFFFFFF, 0.55), color(0xFFFFFF, 0.1)], CGPoint(x: 0, y: rect.maxY), CGPoint(x: 0, y: rect.midY))
    ctx.restoreGState()
}}
ctx.restoreGState()
// Home button
let hb = CGRect(x: 462, y: 172, width: 100, height: 100)
ctx.addEllipse(in: hb); ctx.setFillColor(color(0x1A1A1A)); ctx.fillPath()
ctx.addEllipse(in: hb); ctx.setStrokeColor(color(0x5A5A5A)); ctx.setLineWidth(5); ctx.strokePath()
let sq = CGPath(roundedRect: hb.insetBy(dx: 33, dy: 33), cornerWidth: 7, cornerHeight: 7, transform: nil)
ctx.addPath(sq); ctx.setStrokeColor(color(0xBDBDBD)); ctx.setLineWidth(5); ctx.strokePath()
// Classic gloss over the whole icon
ctx.saveGState()
let gloss = CGMutablePath()
gloss.addEllipse(in: CGRect(x: -S * 0.3, y: S * 0.47, width: S * 1.6, height: S * 1.05))
ctx.addPath(gloss); ctx.clip()
linear([color(0xFFFFFF, 0.42), color(0xFFFFFF, 0.08)], CGPoint(x: 0, y: S), CGPoint(x: 0, y: S * 0.5))
ctx.restoreGState()

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(url.path)")
