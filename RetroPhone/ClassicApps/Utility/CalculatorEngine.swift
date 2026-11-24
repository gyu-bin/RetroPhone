import Foundation

/// Pure, unit-testable arithmetic model of the classic (immediate-execution) calculator.
///
/// - Decimal math (no binary floating point drift: 0.1 + 0.2 = 0.3).
/// - Chained operations: `2 + 3 ×` shows 5 and continues with ×.
/// - `=` repeats the last operation: `2 + 3 = = ` → 5, 8.
/// - `%`, `±`, memory (mc / m+ / m− / mr), C (clear entry) then AC (all clear).
/// - Division by zero puts the calculator in an error state shown as "오류".
/// - Display holds at most 9 digits; larger / tiny results switch to scientific notation.
struct CalculatorEngine: Equatable {
    enum Op: Equatable, CaseIterable { case add, subtract, multiply, divide }

    enum Key: Equatable {
        case digit(Int)
        case decimal
        case op(Op)
        case equals
        case clear
        case sign
        case percent
        case memoryClear, memoryAdd, memorySubtract, memoryRecall
    }

    static let maxDigits = 9

    /// Raw characters while the user is typing a number (e.g. "-12.50"); nil otherwise.
    private(set) var entry: String?
    /// The value shown when not typing (a result, recalled memory, …).
    private(set) var displayValue: Decimal = 0
    private(set) var accumulator: Decimal?
    private(set) var pendingOp: Op?
    /// True once the user supplied the right-hand operand for `pendingOp`.
    private(set) var operandEntered = false
    private(set) var lastOp: Op?
    private(set) var lastOperand: Decimal?
    private(set) var justEvaluated = false
    private(set) var isError = false
    private(set) var memory: Decimal = 0
    private(set) var hasMemory = false

    init() {}

    // MARK: Derived state

    /// The numeric value currently on screen.
    var currentValue: Decimal {
        if let entry { return Self.parse(entry) }
        return displayValue
    }

    /// The operator key that should be drawn highlighted (pressed, waiting for the operand).
    var highlightedOp: Op? { operandEntered ? nil : pendingOp }

    /// "C" clears the current entry, "AC" clears everything.
    var showsAllClear: Bool { entry == nil && !isError }

    /// Display text. `errorText` is substituted by the caller for localization.
    func displayText(errorText: String = "오류") -> String {
        if isError { return errorText }
        if let entry { return Self.formatEntry(entry) }
        return Self.format(displayValue)
    }

    // MARK: Input

    mutating func press(_ key: Key) {
        switch key {
        case .digit(let d): inputDigit(d)
        case .decimal: inputDecimal()
        case .op(let o): inputOp(o)
        case .equals: evaluate()
        case .clear: clear()
        case .sign: toggleSign()
        case .percent: percent()
        case .memoryClear:
            memory = 0
            hasMemory = false
        case .memoryAdd: memoryApply(+1)
        case .memorySubtract: memoryApply(-1)
        case .memoryRecall:
            guard !isError else { return }
            startFreshIfEvaluated()
            displayValue = memory
            entry = nil
            if pendingOp != nil { operandEntered = true }
        }
    }

    mutating func press(_ keys: [Key]) { keys.forEach { press($0) } }

    private mutating func inputDigit(_ d: Int) {
        guard (0...9).contains(d) else { return }
        if isError { resetAll(keepMemory: true) }
        startFreshIfEvaluated()
        if var e = entry {
            guard Self.digitCount(e) < Self.maxDigits else { return }
            if e == "0" { e = String(d) }
            else if e == "-0" { e = "-" + String(d) }
            else { e += String(d) }
            entry = e
        } else {
            entry = String(d)
        }
        operandEntered = true
    }

    private mutating func inputDecimal() {
        if isError { resetAll(keepMemory: true) }
        startFreshIfEvaluated()
        if var e = entry {
            guard !e.contains("."), Self.digitCount(e) < Self.maxDigits else { return }
            e += "."
            entry = e
        } else {
            entry = "0."
        }
        operandEntered = true
    }

    private mutating func inputOp(_ o: Op) {
        guard !isError else { return }
        if let p = pendingOp, let acc = accumulator, operandEntered {
            guard let r = Self.apply(acc, p, currentValue) else { setError(); return }
            displayValue = r
            accumulator = r
        } else if pendingOp == nil {
            let v = currentValue
            accumulator = v
            displayValue = v
        }
        // (pendingOp set but no operand yet → just swap the operator)
        entry = nil
        pendingOp = o
        operandEntered = false
        justEvaluated = false
    }

    private mutating func evaluate() {
        guard !isError else { return }
        if let p = pendingOp, let acc = accumulator {
            let operand = currentValue
            guard let r = Self.apply(acc, p, operand) else { setError(); return }
            lastOp = p
            lastOperand = operand
            displayValue = r
            accumulator = nil
            pendingOp = nil
        } else if let lo = lastOp, let lv = lastOperand {
            guard let r = Self.apply(currentValue, lo, lv) else { setError(); return }
            displayValue = r
        } else {
            displayValue = currentValue
        }
        entry = nil
        operandEntered = false
        justEvaluated = true
    }

    private mutating func clear() {
        if isError { resetAll(keepMemory: true); return }
        if entry != nil {
            entry = nil
            displayValue = 0
            operandEntered = false
        } else {
            resetAll(keepMemory: true)
        }
    }

    private mutating func toggleSign() {
        guard !isError else { return }
        if var e = entry {
            if e.hasPrefix("-") { e.removeFirst() } else { e = "-" + e }
            entry = e
        } else if pendingOp != nil && !operandEntered {
            entry = "-0"
            operandEntered = true
        } else if displayValue != 0 {
            displayValue = -displayValue
        }
    }

    private mutating func percent() {
        guard !isError else { return }
        let v = currentValue
        let r: Decimal
        if let acc = accumulator, let p = pendingOp, p == .add || p == .subtract {
            r = acc * v / 100
        } else {
            r = v / 100
        }
        displayValue = r
        entry = nil
        if pendingOp != nil { operandEntered = true }
    }

    private mutating func memoryApply(_ sign: Int) {
        guard !isError else { return }
        let v = currentValue
        memory = sign > 0 ? memory + v : memory - v
        hasMemory = true
        displayValue = v
        entry = nil
    }

    private mutating func startFreshIfEvaluated() {
        guard justEvaluated else { return }
        justEvaluated = false
        lastOp = nil
        lastOperand = nil
        accumulator = nil
    }

    private mutating func setError() {
        isError = true
        entry = nil
        accumulator = nil
        pendingOp = nil
        lastOp = nil
        lastOperand = nil
        operandEntered = false
        justEvaluated = false
    }

    private mutating func resetAll(keepMemory: Bool) {
        let m = memory, hm = hasMemory
        self = CalculatorEngine()
        if keepMemory { memory = m; hasMemory = hm }
    }

    // MARK: Pure helpers

    static func apply(_ a: Decimal, _ op: Op, _ b: Decimal) -> Decimal? {
        let r: Decimal
        switch op {
        case .add: r = a + b
        case .subtract: r = a - b
        case .multiply: r = a * b
        case .divide:
            guard b != 0 else { return nil }
            r = a / b
        }
        return r.isNaN ? nil : r
    }

    static func digitCount(_ s: String) -> Int { s.filter(\.isNumber).count }

    static func parse(_ s: String) -> Decimal {
        var t = s
        if t.hasSuffix(".") { t.removeLast() }
        if t == "-0" || t == "-" || t.isEmpty { return 0 }
        return Decimal(string: t, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private static let posix = Locale(identifier: "en_US")

    /// Formats the characters being typed, keeping a trailing "." and trailing zeros.
    static func formatEntry(_ s: String) -> String {
        var body = s
        let negative = body.hasPrefix("-")
        if negative { body.removeFirst() }
        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let intPart = parts.first.map(String.init) ?? "0"
        let f = NumberFormatter()
        f.locale = posix
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        let grouped = f.string(from: NSDecimalNumber(string: intPart.isEmpty ? "0" : intPart)) ?? intPart
        var out = (negative ? "-" : "") + grouped
        if parts.count > 1 { out += "." + parts[1] }
        return out
    }

    /// Formats a result to at most `maxDigits` significant digits with group separators.
    static func format(_ value: Decimal) -> String {
        if value.isNaN { return "0" }
        let absValue = value < 0 ? -value : value
        if absValue == 0 { return "0" }
        let upper = Decimal(string: "999999999.5")!
        let lower = Decimal(string: "0.00000001")!
        if absValue >= upper || absValue < lower {
            let f = NumberFormatter()
            f.locale = posix
            f.numberStyle = .scientific
            f.maximumFractionDigits = 5
            f.exponentSymbol = "e"
            return f.string(from: NSDecimalNumber(decimal: value)) ?? "0"
        }
        let intDigits = String(Int(truncating: NSDecimalNumber(decimal: absValue))).count
        let f = NumberFormatter()
        f.locale = posix
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.roundingMode = .halfUp
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = max(0, maxDigits - intDigits)
        let s = f.string(from: NSDecimalNumber(decimal: value)) ?? "0"
        return s == "-0" ? "0" : s
    }
}
