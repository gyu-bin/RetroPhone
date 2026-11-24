import XCTest
@testable import RetroPhone

final class CalculatorEngineTests: XCTestCase {
    private func run(_ keys: [CalculatorEngine.Key]) -> CalculatorEngine {
        var e = CalculatorEngine()
        e.press(keys)
        return e
    }

    func testBasicArithmeticAndDecimalPrecision() {
        XCTAssertEqual(run([.digit(1), .op(.add), .digit(2), .equals]).currentValue, 3)
        // Decimal math: 0.1 + 0.2 must be exactly 0.3.
        let e = run([.decimal, .digit(1), .op(.add), .decimal, .digit(2), .equals])
        XCTAssertEqual(e.currentValue, Decimal(string: "0.3"))
    }

    func testChainedOperationsAndRepeatEquals() {
        // 2 + 3 × 4 on a classic calculator evaluates left to right: (2+3)×4 = 20.
        XCTAssertEqual(run([.digit(2), .op(.add), .digit(3), .op(.multiply), .digit(4), .equals]).currentValue, 20)
        // "=" repeats the last operation: 5 + 2 = = → 9.
        XCTAssertEqual(run([.digit(5), .op(.add), .digit(2), .equals, .equals]).currentValue, 9)
    }

    func testDivideByZeroIsError() {
        let e = run([.digit(1), .op(.divide), .digit(0), .equals])
        XCTAssertTrue(e.isError)
        XCTAssertEqual(e.displayText(errorText: "오류"), "오류")
        var cleared = e
        cleared.press(.clear)
        XCTAssertFalse(cleared.isError)
    }

    func testSignAndMemory() {
        XCTAssertEqual(run([.digit(7), .sign]).currentValue, -7)
        let e = run([.digit(4), .memoryAdd, .clear, .digit(1), .memoryRecall])
        XCTAssertEqual(e.currentValue, 4)
        XCTAssertTrue(e.hasMemory)
    }

    func testDigitLimit() {
        let e = run(Array(repeating: .digit(9), count: 12))
        XCTAssertLessThanOrEqual(CalculatorEngine.digitCount(e.displayText()), CalculatorEngine.maxDigits)
    }
}

final class BrowserURLTests: XCTestCase {
    func testDomainsBecomeHTTPS() {
        XCTAssertEqual(BrowserURL.resolve("naver.com", engine: .google).absoluteString, "https://naver.com")
        XCTAssertEqual(BrowserURL.resolve("https://example.com/a?b=1", engine: .google).absoluteString, "https://example.com/a?b=1")
    }

    func testSearchTermsGoToEngineAndAreEncoded() {
        let url = BrowserURL.resolve("레트로 아이폰 + 4", engine: .google)
        XCTAssertEqual(url.host(), "www.google.com")
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
        XCTAssertEqual(q, "레트로 아이폰 + 4")
        XCTAssertFalse(url.absoluteString.contains(" "))
    }

    func testNaverEngine() {
        let url = BrowserURL.resolve("날씨", engine: .naver)
        XCTAssertTrue(url.host()?.contains("naver.com") ?? false)
    }
}
