import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// A pure, value-type description of a subtle "sensor look" inspired by an older iPhone camera.
///
/// These are *interpretations*, not measurements: gentle colour casts, tone curves, grain and
/// sharpness chosen to evoke how photos from those phones tended to look, while keeping skin
/// tones natural. Everything here is `nonisolated` so it can run on a background queue and be
/// unit-tested without UI.
///
/// Processing order (see `apply(to:)`):
/// 1. Resolution: Lanczos downscale to `targetMegapixels` (never upscales).
/// 2. White balance: per-channel gains derived from `temperature` / `tint` (linear light).
/// 3. Perceptual stage (sRGB-encoded values): saturation / contrast / brightness, 5-point tone
///    curve, highlight tint, luminance grain.
/// 4. Detail: luminance sharpening (`sharpness > 0`) or a softening blur (`sharpness < 0`).
nonisolated struct RetroFilterPreset: Equatable, Sendable {
    var name: String
    /// -1 (cool / blue) … +1 (warm / amber).
    var temperature: Double
    /// -1 (green) … +1 (magenta).
    var tint: Double
    /// 1 = unchanged.
    var saturation: Double
    /// 1 = unchanged.
    var contrast: Double
    /// 0 = unchanged (additive, -1 … 1).
    var brightness: Double
    /// Exactly five control points in sRGB-encoded space, x ascending from 0 to 1.
    var toneCurve: [CGPoint]
    /// Per-channel highlight shift (r, g, b): adds `k · v³` so only bright values are tinted.
    var highlightTint: SIMD3<Double>
    /// Peak luminance deviation at mid-grey (0 … ~0.05). 0 disables grain.
    var noiseAmount: Double
    /// > 0: luminance sharpen amount (CISharpenLuminance). < 0: softening blur radius in pixels.
    var sharpness: Double
    /// Output resolution target in megapixels; nil keeps the captured resolution.
    var targetMegapixels: Double?

    // MARK: Presets

    /// iPhone 4 (2010, 5 MP back camera): slightly soft, warm yellow-green cast, limited dynamic
    /// range (shadows block up a little, highlights roll off early and stay a touch dull),
    /// visible but moderate luminance noise.
    static let iPhone4 = RetroFilterPreset(
        name: "iPhone 4",
        temperature: 0.32, tint: -0.28,
        saturation: 0.93, contrast: 0.98, brightness: 0,
        toneCurve: [CGPoint(x: 0, y: 0), CGPoint(x: 0.10, y: 0.065), CGPoint(x: 0.5, y: 0.51),
                    CGPoint(x: 0.85, y: 0.92), CGPoint(x: 1, y: 0.97)],
        highlightTint: .zero,
        noiseAmount: 0.022,
        sharpness: -0.6,
        targetMegapixels: 5.0)

    /// iPhone 4S (2011, 8 MP): more neutral with a gentle warmth, better dynamic range,
    /// light noise, mild sharpening.
    static let iPhone4S = RetroFilterPreset(
        name: "iPhone 4S",
        temperature: 0.18, tint: -0.06,
        saturation: 1.0, contrast: 1.0, brightness: 0,
        toneCurve: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.24), CGPoint(x: 0.5, y: 0.505),
                    CGPoint(x: 0.75, y: 0.765), CGPoint(x: 1, y: 1)],
        highlightTint: .zero,
        noiseAmount: 0.012,
        sharpness: 0.15,
        targetMegapixels: 8.0)

    /// iPhone 5 (2012, 8 MP): cooler / neutral balance, slight purple-ish cast in bright areas,
    /// crisper sharpening, very light noise.
    static let iPhone5 = RetroFilterPreset(
        name: "iPhone 5",
        temperature: -0.10, tint: 0.06,
        saturation: 1.04, contrast: 1.03, brightness: 0,
        toneCurve: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.245), CGPoint(x: 0.5, y: 0.5),
                    CGPoint(x: 0.75, y: 0.76), CGPoint(x: 1, y: 1)],
        highlightTint: SIMD3(0.010, -0.022, 0.018),
        noiseAmount: 0.008,
        sharpness: 0.45,
        targetMegapixels: 8.0)

    // MARK: Pure helpers (unit-testable)

    /// Linear-light RGB gains for the white-balance shift. Normalised so a neutral grey keeps
    /// its Rec.709 luminance (the look changes colour, not exposure).
    var channelGains: SIMD3<Double> {
        let r = 1 + 0.10 * temperature + 0.03 * tint
        let g = 1 - 0.06 * tint
        let b = 1 - 0.12 * temperature + 0.03 * tint
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        guard luma > 0 else { return SIMD3(1, 1, 1) }
        return SIMD3(r / luma, g / luma, b / luma)
    }

    /// Uniform scale factor that brings `width × height` down to `targetMegapixels` (≤ 1).
    func scaleFactor(width: Double, height: Double) -> Double {
        guard let mp = targetMegapixels, mp > 0, width > 0, height > 0 else { return 1 }
        return min(1, (mp * 1_000_000 / (width * height)).squareRoot())
    }

    /// Output pixel size for a given input size (rounded down to whole pixels).
    func outputSize(width: Double, height: Double) -> CGSize {
        let s = scaleFactor(width: width, height: height)
        return CGSize(width: (width * s).rounded(.down), height: (height * s).rounded(.down))
    }

    // MARK: Core Image pipeline

    /// - Parameters:
    ///   - preview: live-preview variant: keeps the input resolution and skips grain (a static
    ///     grain pattern over a moving image reads as dirt on the lens, not sensor noise).
    ///   - pixelScale: how much the input was already downscaled (blur radius follows it).
    func apply(to input: CIImage, preview: Bool = false, pixelScale: Double = 1) -> CIImage {
        var image = input

        // 1. Resolution
        let s = preview ? 1 : scaleFactor(width: input.extent.width, height: input.extent.height)
        if s < 0.999 {
            image = image.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: s,
                kCIInputAspectRatioKey: 1.0,
            ])
            let e = image.extent
            let x = e.minX.rounded(.up), y = e.minY.rounded(.up)
            image = image.cropped(to: CGRect(x: x, y: y,
                                             width: e.maxX.rounded(.down) - x,
                                             height: e.maxY.rounded(.down) - y))
        }
        let extent = image.extent

        // 2. White balance (linear light)
        let g = channelGains
        image = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: g.x, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: g.y, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: g.z, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])

        // 3. Perceptual stage
        image = image.applyingFilter("CILinearToSRGBToneCurve")
        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: saturation,
            kCIInputContrastKey: contrast,
            kCIInputBrightnessKey: brightness,
        ])
        if toneCurve.count == 5 {
            image = image.applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": CIVector(cgPoint: toneCurve[0]),
                "inputPoint1": CIVector(cgPoint: toneCurve[1]),
                "inputPoint2": CIVector(cgPoint: toneCurve[2]),
                "inputPoint3": CIVector(cgPoint: toneCurve[3]),
                "inputPoint4": CIVector(cgPoint: toneCurve[4]),
            ])
        }
        if highlightTint != .zero {
            let h = highlightTint
            image = image.applyingFilter("CIColorPolynomial", parameters: [
                "inputRedCoefficients": CIVector(x: 0, y: 1, z: 0, w: h.x),
                "inputGreenCoefficients": CIVector(x: 0, y: 1, z: 0, w: h.y),
                "inputBlueCoefficients": CIVector(x: 0, y: 1, z: 0, w: h.z),
                "inputAlphaCoefficients": CIVector(x: 0, y: 1, z: 0, w: 0),
            ])
        }
        if noiseAmount > 0 && !preview {
            image = addLuminanceGrain(to: image, extent: extent)
        }
        image = image.applyingFilter("CISRGBToneCurveToLinear")

        // 4. Detail
        if sharpness > 0 {
            image = image.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: sharpness,
                kCIInputRadiusKey: 1.5,
            ])
        } else if sharpness < 0 {
            image = image.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: -sharpness * (preview ? max(pixelScale, 0.5) : 1)])
        }
        return image.cropped(to: extent)
    }

    /// Monochrome grain blended with soft light: neutral at 0.5, strongest in the mid-tones,
    /// so it reads like sensor noise rather than a colour overlay.
    private func addLuminanceGrain(to image: CIImage, extent: CGRect) -> CIImage {
        guard let random = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }
        let amplitude = min(1, noiseAmount * 4)
        let bias = 0.5 - 0.5 * amplitude
        let grain = random
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: amplitude, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: amplitude, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: amplitude, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1),
            ])
            .cropped(to: extent)
        return grain.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
    }
}

/// Encodes filtered captures. Runs off the main thread.
nonisolated enum RetroPhotoProcessor {
    static let context = CIContext(options: [.cacheIntermediates: false])

    /// Applies `preset` to an encoded photo (HEIC/JPEG) and re-encodes it as JPEG, keeping the
    /// original metadata (EXIF, orientation, GPS) minus the stale pixel-dimension tags.
    static func process(_ data: Data, preset: RetroFilterPreset) -> Data? {
        guard let input = CIImage(data: data) else { return nil }
        let output = preset.apply(to: input).settingProperties(metadata(from: input.properties))
        let colorSpace = input.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return context.jpegRepresentation(of: output, colorSpace: colorSpace, options: [quality: 0.92])
    }

    static func metadata(from properties: [String: Any]) -> [String: Any] {
        var meta = properties
        meta.removeValue(forKey: kCGImagePropertyPixelWidth as String)
        meta.removeValue(forKey: kCGImagePropertyPixelHeight as String)
        if var exif = meta[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension as String)
            exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension as String)
            meta[kCGImagePropertyExifDictionary as String] = exif
        }
        return meta
    }

    /// Re-encodes a library photo as JPEG (used for sharing), preserving metadata.
    static func jpeg(from data: Data) -> Data? {
        guard let image = CIImage(data: data) else { return nil }
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return context.jpegRepresentation(of: image, colorSpace: colorSpace, options: [quality: 0.95])
    }

    /// Small, orientation-corrected preview of encoded image data.
    static func thumbnail(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
