import SwiftUI
import UIKit

/// Procedurally generated, original wallpapers (rendered once per size and cached).
enum WallpaperRenderer {
    private static var cache: [String: UIImage] = [:]

    static func image(for choice: WallpaperChoice, size: CGSize) -> UIImage? {
        switch choice {
        case .custom(let file): return FileStore.loadImage(file)
        case .builtin(let w):
            let key = "\(w.rawValue)-\(Int(size.width))x\(Int(size.height))"
            if let img = cache[key] { return img }
            let img = render(w, size: size)
            cache[key] = img
            return img
        }
    }

    static func render(_ w: BuiltinWallpaper, size: CGSize) -> UIImage {
        let size = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = min(UIScreen.main.scale, 3)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            // String.hashValue is randomized per launch, so derive a stable seed from the name.
            let seed = w.rawValue.unicodeScalars.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1.value) }
            var rng = SeededRandom(seed: seed)
            switch w {
            case .droplets: drawDroplets(c, size, &rng)
            case .aurora: drawAurora(c, size, &rng)
            case .linen: drawLinen(c, size, &rng)
            case .night: drawNight(c, size, &rng)
            case .sunset: drawSunset(c, size)
            case .wave: drawWave(c, size, &rng)
            }
        }
    }

    private static func linear(_ c: CGContext, _ size: CGSize, _ colors: [UIColor], _ locations: [CGFloat]? = nil) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: cs, colors: colors.map(\.cgColor) as CFArray, locations: locations)!
        c.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width * 0.3, y: size.height),
                             options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func ui(_ hex: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    /// Water droplets on dark blue-green glass.
    private static func drawDroplets(_ c: CGContext, _ size: CGSize, _ rng: inout SeededRandom) {
        linear(c, size, [ui(0x1E4E63), ui(0x0E2A3C), ui(0x07141F)], [0, 0.55, 1])
        // Soft out-of-focus light blobs
        for _ in 0..<6 {
            let r = CGFloat(rng.next(in: 80...200)) * size.width / 390
            let p = CGPoint(x: CGFloat(rng.next(in: 0...1)) * size.width, y: CGFloat(rng.next(in: 0...1)) * size.height)
            let g = CGGradient(colorsSpace: nil, colors: [ui(0x4FA3B8, 0.22).cgColor, ui(0x4FA3B8, 0).cgColor] as CFArray, locations: nil)!
            c.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
        }
        let count = max(40, Int(size.width * size.height / 1500))
        var drops: [(CGPoint, CGFloat)] = []
        for _ in 0..<count {
            let big = rng.next(in: 0...1) < 0.12
            let r = CGFloat(big ? rng.next(in: 9...22) : rng.next(in: 1.5...7)) * size.width / 390
            drops.append((CGPoint(x: CGFloat(rng.next(in: 0...1)) * size.width,
                                  y: CGFloat(rng.next(in: 0...1)) * size.height), r))
        }
        for (p, r) in drops.sorted(by: { $0.1 < $1.1 }) {
            let stretch = 1 + CGFloat(rng.next(in: 0...0.25))
            let rect = CGRect(x: p.x - r, y: p.y - r * stretch, width: r * 2, height: r * 2 * stretch)
            // Shadow cast below the droplet
            c.setFillColor(ui(0x000000, 0.35).cgColor)
            c.fillEllipse(in: rect.offsetBy(dx: r * 0.12, dy: r * 0.22))
            // Refraction body: dark rim on top, bright bottom (light refracted through the lens)
            c.saveGState()
            c.addEllipse(in: rect); c.clip()
            let body = CGGradient(colorsSpace: nil, colors: [ui(0x06121A, 0.55).cgColor, ui(0x2D6E82, 0.5).cgColor, ui(0x9FE0EE, 0.75).cgColor] as CFArray,
                                  locations: [0, 0.6, 1])!
            c.drawLinearGradient(body, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
            c.restoreGState()
            // Specular highlight
            let hl = CGRect(x: rect.minX + r * 0.45, y: rect.minY + r * 0.3, width: r * 0.55, height: r * 0.4)
            c.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            c.fillEllipse(in: hl)
            // Rim
            c.setStrokeColor(UIColor.white.withAlphaComponent(0.12).cgColor)
            c.setLineWidth(max(0.5, r * 0.06))
            c.strokeEllipse(in: rect)
        }
    }

    private static func drawAurora(_ c: CGContext, _ size: CGSize, _ rng: inout SeededRandom) {
        linear(c, size, [ui(0x050B1E), ui(0x0B1E3A), ui(0x02040A)], [0, 0.5, 1])
        let colors: [UInt32] = [0x2FE39A, 0x1FB5C9, 0x8A4FE0, 0x2FE39A]
        for (i, hex) in colors.enumerated() {
            c.saveGState()
            let y = size.height * (0.2 + CGFloat(i) * 0.12)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: -50, y: y))
            path.addCurve(to: CGPoint(x: size.width + 50, y: y - 40),
                          controlPoint1: CGPoint(x: size.width * 0.3, y: y - 140),
                          controlPoint2: CGPoint(x: size.width * 0.7, y: y + 120))
            c.setShadow(offset: .zero, blur: 40, color: ui(hex, 0.9).cgColor)
            c.setStrokeColor(ui(hex, 0.35).cgColor)
            c.setLineWidth(46)
            c.addPath(path.cgPath); c.strokePath()
            c.restoreGState()
        }
        drawStars(c, size, &rng, count: 120, maxY: 1)
    }

    private static func drawLinen(_ c: CGContext, _ size: CGSize, _ rng: inout SeededRandom) {
        c.setFillColor(ui(0x4A4D52).cgColor); c.fill(CGRect(origin: .zero, size: size))
        for _ in 0..<Int(size.height * 1.4) {
            let y = CGFloat(rng.next(in: 0...1)) * size.height
            c.setFillColor(UIColor(white: CGFloat(rng.next(in: 0.15...0.45)), alpha: 0.18).cgColor)
            c.fill(CGRect(x: 0, y: y, width: size.width, height: 0.6))
        }
        for _ in 0..<Int(size.width * 1.4) {
            let x = CGFloat(rng.next(in: 0...1)) * size.width
            c.setFillColor(UIColor(white: CGFloat(rng.next(in: 0.15...0.5)), alpha: 0.15).cgColor)
            c.fill(CGRect(x: x, y: 0, width: 0.6, height: size.height))
        }
    }

    private static func drawNight(_ c: CGContext, _ size: CGSize, _ rng: inout SeededRandom) {
        linear(c, size, [ui(0x02030A), ui(0x0A1638), ui(0x1C2D5E)], [0, 0.6, 1])
        drawStars(c, size, &rng, count: 260, maxY: 0.85)
        // Hills silhouette
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 0, y: size.height))
        p.addLine(to: CGPoint(x: 0, y: size.height * 0.84))
        p.addCurve(to: CGPoint(x: size.width, y: size.height * 0.8),
                   controlPoint1: CGPoint(x: size.width * 0.35, y: size.height * 0.74),
                   controlPoint2: CGPoint(x: size.width * 0.6, y: size.height * 0.9))
        p.addLine(to: CGPoint(x: size.width, y: size.height)); p.close()
        c.setFillColor(ui(0x03050C).cgColor); c.addPath(p.cgPath); c.fillPath()
    }

    /// iOS 7-era style: bright blue→violet→coral gradient with soft light waves and bokeh.
    private static func drawWave(_ c: CGContext, _ size: CGSize, _ rng: inout SeededRandom) {
        linear(c, size, [ui(0x1C8BD9), ui(0x3D5BD6), ui(0x8A4FC8), ui(0xE7678F), ui(0xF6A25E)], [0, 0.3, 0.55, 0.8, 1])
        let w = size.width, h = size.height
        // Translucent light bands sweeping across.
        for i in 0..<4 {
            let y0 = h * (0.25 + CGFloat(i) * 0.16)
            let amp = h * CGFloat(rng.next(in: 0.05...0.11))
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w * 0.1, y: y0))
            p.addCurve(to: CGPoint(x: w * 1.1, y: y0 - amp),
                       control1: CGPoint(x: w * 0.3, y: y0 - amp * 2.2),
                       control2: CGPoint(x: w * 0.7, y: y0 + amp * 1.6))
            p.addLine(to: CGPoint(x: w * 1.1, y: h * 1.1))
            p.addLine(to: CGPoint(x: -w * 0.1, y: h * 1.1))
            p.closeSubpath()
            c.addPath(p)
            c.setFillColor(ui(0xFFFFFF, 0.06 + CGFloat(i) * 0.015).cgColor)
            c.fillPath()
        }
        // Soft out-of-focus circles.
        for _ in 0..<14 {
            let r = CGFloat(rng.next(in: 20...90)) * w / 390
            let p = CGPoint(x: CGFloat(rng.next(in: 0...1)) * w, y: CGFloat(rng.next(in: 0...1)) * h)
            let a = CGFloat(rng.next(in: 0.06...0.16))
            let g = CGGradient(colorsSpace: nil, colors: [ui(0xFFFFFF, a).cgColor, ui(0xFFFFFF, 0).cgColor] as CFArray,
                               locations: [0.6, 1])!
            c.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
        }
    }

    private static func drawSunset(_ c: CGContext, _ size: CGSize) {
        linear(c, size, [ui(0x2A1B4A), ui(0xC2456A), ui(0xF59A4A), ui(0xFCD58A)], [0, 0.45, 0.75, 1])
        let sun = CGPoint(x: size.width * 0.55, y: size.height * 0.72)
        let g = CGGradient(colorsSpace: nil, colors: [ui(0xFFF4C0).cgColor, ui(0xFFC060, 0).cgColor] as CFArray, locations: nil)!
        c.drawRadialGradient(g, startCenter: sun, startRadius: 0, endCenter: sun, endRadius: size.width * 0.35, options: [])
        let sea = CGRect(x: 0, y: size.height * 0.76, width: size.width, height: size.height * 0.24)
        let sg = CGGradient(colorsSpace: nil, colors: [ui(0x6A3A6A).cgColor, ui(0x1A1030).cgColor] as CFArray, locations: nil)!
        c.saveGState(); c.clip(to: sea)
        c.drawLinearGradient(sg, start: CGPoint(x: 0, y: sea.minY), end: CGPoint(x: 0, y: sea.maxY), options: [])
        c.restoreGState()
    }

    private static func drawStars(_ c: CGContext, _ size: CGSize, _ rng: inout SeededRandom, count: Int, maxY: CGFloat) {
        for _ in 0..<count {
            let r = CGFloat(rng.next(in: 0.3...1.4))
            let p = CGPoint(x: CGFloat(rng.next(in: 0...1)) * size.width, y: CGFloat(rng.next(in: 0...1)) * size.height * maxY)
            c.setFillColor(UIColor.white.withAlphaComponent(CGFloat(rng.next(in: 0.3...1))).cgColor)
            c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
    }
}

/// Deterministic RNG so wallpapers look identical on every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func nextUInt() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(nextUInt() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

/// Full-bleed wallpaper view.
struct WallpaperView: View {
    var choice: WallpaperChoice
    var body: some View {
        GeometryReader { g in
            if let img = WallpaperRenderer.image(for: choice, size: g.size) {
                Image(uiImage: img).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped()
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
