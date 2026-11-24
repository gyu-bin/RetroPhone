// Renders RetroPhone's app icon (1024×1024) with CoreGraphics, following the design reference:
// a charcoal glass tile with a sweeping gloss and a classic phone (steel band, black glass face,
// diagonal screen glare, home button). iOS applies the rounded-corner mask itself, so the tile
// background fills the whole square.
// Usage: swift scripts/make_app_icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Work in top-left-origin coordinates like UIKit.
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func linear(_ colors: [CGColor], _ from: CGPoint, _ to: CGPoint, _ locs: [CGFloat]? = nil) {
    let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func clip(_ path: CGPath, _ draw: () -> Void) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip(); draw(); ctx.restoreGState()
}

// 1. Charcoal tile
linear([color(0x55575B), color(0x2E2F33), color(0x1C1D20)], CGPoint(x: 0, y: 0), CGPoint(x: 0, y: S), [0, 0.45, 1])

// 2. Sweeping gloss over the upper part of the tile (curved lower edge rising to the right)
let gloss = CGMutablePath()
gloss.move(to: CGPoint(x: 0, y: 0))
gloss.addLine(to: CGPoint(x: S, y: 0))
gloss.addLine(to: CGPoint(x: S, y: S * 0.31))
gloss.addCurve(to: CGPoint(x: 0, y: S * 0.47),
               control1: CGPoint(x: S * 0.62, y: S * 0.50), control2: CGPoint(x: S * 0.22, y: S * 0.52))
gloss.closeSubpath()
clip(gloss) {
    linear([color(0xFFFFFF, 0.20), color(0xFFFFFF, 0.06)], CGPoint(x: 0, y: 0), CGPoint(x: 0, y: S * 0.5))
}

// 3. Phone body
let body = CGRect(x: S * 0.335, y: S * 0.205, width: S * 0.33, height: S * 0.585)
let bodyRadius = S * 0.062
// Soft shadow under the phone
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: S * 0.018), blur: S * 0.035, color: color(0x000000, 0.65))
ctx.addPath(rounded(body, bodyRadius)); ctx.setFillColor(color(0x0A0A0A)); ctx.fillPath()
ctx.restoreGState()

// Side buttons (mute + volume) on the left edge
for (i, h) in [(0, 0.035), (1, 0.048), (2, 0.048)] as [(Int, Double)] {
    let y = body.minY + body.height * (0.14 + CGFloat(i) * 0.09)
    let btn = CGRect(x: body.minX - S * 0.012, y: y, width: S * 0.016, height: S * CGFloat(h))
    clip(rounded(btn, S * 0.006)) {
        linear([color(0xF2F2F2), color(0x9C9EA2), color(0xE6E6E6)], CGPoint(x: btn.minX, y: 0), CGPoint(x: btn.maxX, y: 0))
    }
}

// Stainless steel band
clip(rounded(body, bodyRadius)) {
    linear([color(0xFAFAFA), color(0xB9BBBF), color(0xEDEDED), color(0x8E9095)],
           CGPoint(x: body.minX, y: body.minY), CGPoint(x: body.maxX, y: body.maxY), [0, 0.35, 0.6, 1])
}
// Black glass face
let face = body.insetBy(dx: S * 0.009, dy: S * 0.009)
let facePath = rounded(face, bodyRadius - S * 0.009)
clip(facePath) {
    linear([color(0x141416), color(0x050506)], CGPoint(x: 0, y: face.minY), CGPoint(x: 0, y: face.maxY))
}

// Earpiece + front camera
let ear = CGRect(x: face.midX - S * 0.034, y: face.minY + S * 0.058, width: S * 0.068, height: S * 0.016)
clip(rounded(ear, ear.height / 2)) {
    linear([color(0x2A2B2E), color(0x5A5C61)], CGPoint(x: 0, y: ear.minY), CGPoint(x: 0, y: ear.maxY))
}
ctx.addPath(rounded(ear, ear.height / 2)); ctx.setStrokeColor(color(0x8A8C90)); ctx.setLineWidth(2.5); ctx.strokePath()
let cam = CGRect(x: ear.minX - S * 0.034, y: ear.midY - S * 0.008, width: S * 0.016, height: S * 0.016)
ctx.setFillColor(color(0x1C2230)); ctx.fillEllipse(in: cam)
ctx.setFillColor(color(0x6C7488, 0.9)); ctx.fillEllipse(in: cam.insetBy(dx: S * 0.0045, dy: S * 0.0045))

// Screen
let screen = CGRect(x: face.minX + S * 0.024, y: face.minY + S * 0.115, width: face.width - S * 0.048, height: S * 0.33)
clip(CGPath(rect: screen, transform: nil)) {
    linear([color(0x3A3B3F), color(0x26272A), color(0x1C1D20)], CGPoint(x: 0, y: screen.minY), CGPoint(x: 0, y: screen.maxY), [0, 0.5, 1])
}

// Diagonal glare across the glass (upper-right wedge), like light catching the front panel
clip(facePath) {
    let glare = CGMutablePath()
    glare.move(to: CGPoint(x: face.minX + face.width * 0.48, y: face.minY))
    glare.addLine(to: CGPoint(x: face.maxX, y: face.minY))
    glare.addLine(to: CGPoint(x: face.maxX, y: face.minY + face.height * 0.40))
    glare.addLine(to: CGPoint(x: face.minX, y: face.minY + face.height * 0.62))
    glare.addLine(to: CGPoint(x: face.minX, y: face.minY + face.height * 0.52))
    glare.closeSubpath()
    // Fan shape: wedge between a near-vertical line and a shallow diagonal.
    let wedge = CGMutablePath()
    wedge.move(to: CGPoint(x: face.minX + face.width * 0.50, y: face.minY))
    wedge.addLine(to: CGPoint(x: face.maxX, y: face.minY))
    wedge.addLine(to: CGPoint(x: face.maxX, y: face.minY + face.height * 0.37))
    wedge.addLine(to: CGPoint(x: face.minX + face.width * 0.84, y: face.maxY))
    wedge.closeSubpath()
    ctx.saveGState(); ctx.addPath(wedge); ctx.clip()
    linear([color(0xFFFFFF, 0.16), color(0xFFFFFF, 0.05)], CGPoint(x: face.maxX, y: face.minY), CGPoint(x: face.midX, y: face.midY))
    ctx.restoreGState()
    // Lower shallow band: slightly darker below the diagonal
    let band = CGMutablePath()
    band.move(to: CGPoint(x: face.minX, y: face.minY + face.height * 0.62))
    band.addLine(to: CGPoint(x: face.maxX, y: face.minY + face.height * 0.40))
    band.addLine(to: CGPoint(x: face.maxX, y: face.maxY))
    band.addLine(to: CGPoint(x: face.minX, y: face.maxY))
    band.closeSubpath()
    ctx.addPath(band); ctx.setFillColor(color(0x000000, 0.18)); ctx.fillPath()
    _ = glare
}

// Home button
let hb = CGRect(x: face.midX - S * 0.033, y: screen.maxY + S * 0.024, width: S * 0.066, height: S * 0.066)
clip(CGPath(ellipseIn: hb, transform: nil)) {
    linear([color(0x020202), color(0x2C2D30)], CGPoint(x: 0, y: hb.minY), CGPoint(x: 0, y: hb.maxY))
}
ctx.addEllipse(in: hb); ctx.setStrokeColor(color(0x3E4044)); ctx.setLineWidth(3); ctx.strokePath()
let sq = hb.insetBy(dx: S * 0.021, dy: S * 0.021)
ctx.addPath(rounded(sq, S * 0.006)); ctx.setStrokeColor(color(0xD4D5D8)); ctx.setLineWidth(3.5); ctx.strokePath()

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(url.path)")
