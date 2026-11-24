import XCTest
import CoreImage
@testable import RetroPhone

final class RetroFilterPresetTests: XCTestCase {
    func testWhiteBalanceGainsPreserveLuminance() {
        for preset in [RetroFilterPreset.iPhone4, .iPhone4S, .iPhone5] {
            let g = preset.channelGains
            let luma = 0.2126 * g.x + 0.7152 * g.y + 0.0722 * g.z
            XCTAssertEqual(luma, 1, accuracy: 1e-9, preset.name)
        }
        // iPhone 4 is warm (red > blue); iPhone 5 is cooler (blue > red).
        XCTAssertGreaterThan(RetroFilterPreset.iPhone4.channelGains.x, RetroFilterPreset.iPhone4.channelGains.z)
        XCTAssertGreaterThan(RetroFilterPreset.iPhone5.channelGains.z, RetroFilterPreset.iPhone5.channelGains.x)
    }

    func testDownscalesToTargetMegapixelsNeverUpscales() {
        let p = RetroFilterPreset.iPhone4  // 5 MP
        let out = p.outputSize(width: 4032, height: 3024)  // 12 MP
        XCTAssertEqual(out.width * out.height / 1_000_000, 5, accuracy: 0.05)
        XCTAssertEqual(out.width / out.height, 4032.0 / 3024.0, accuracy: 0.002)
        XCTAssertEqual(p.scaleFactor(width: 1000, height: 1000), 1, "no upscaling")
    }

    func testPresetsAreSubtleAndCurvesValid() {
        for p in [RetroFilterPreset.iPhone4, .iPhone4S, .iPhone5] {
            XCTAssertEqual(p.toneCurve.count, 5, p.name)
            XCTAssertEqual(p.toneCurve.map(\.x), p.toneCurve.map(\.x).sorted(), p.name)
            XCTAssertTrue((0.85...1.15).contains(p.saturation), "\(p.name) saturation stays natural")
            XCTAssertLessThanOrEqual(p.noiseAmount, 0.05, "\(p.name) noise stays moderate")
        }
    }

    func testPipelineProducesImageOfExpectedSize() {
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 4000, height: 3000))
        let out = RetroFilterPreset.iPhone4.apply(to: input)
        XCTAssertEqual(out.extent.width * out.extent.height / 1_000_000, 5, accuracy: 0.1)
    }
}

final class VUScaleTests: XCTestCase {
    func testMapping() {
        XCTAssertEqual(VUScale.fraction(forVU: VUScale.minVU), 0, accuracy: 1e-9)
        XCTAssertEqual(VUScale.fraction(forVU: VUScale.maxVU), 1, accuracy: 1e-9)
        XCTAssertEqual(VUScale.fraction(forDBFS: -.infinity), 0)
        XCTAssertEqual(VUScale.fraction(forDBFS: VUScale.referenceDBFS), VUScale.fraction(forVU: 0), accuracy: 1e-9)
        XCTAssertLessThan(VUScale.fraction(forVU: -10), VUScale.fraction(forVU: 0))
    }
}
