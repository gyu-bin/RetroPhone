import SwiftUI
import UIKit

// Shared building blocks for the Communication apps (Phone, Messages, Contacts, Calendar, Clock).
// Everything here is prefixed `Comm` to avoid clashing with other modules.

// MARK: - iOS 4 black tab bar (UITabBar)

struct CommTabItem<T: Hashable>: Identifiable {
    var tag: T
    var title: String
    var systemImage: String
    var id: T { tag }
}

struct CommTabBar<T: Hashable>: View {
    var items: [CommTabItem<T>]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                tabButton(item)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(height: 49)
        .background(background)
    }

    private func tabButton(_ item: CommTabItem<T>) -> some View {
        let selected = item.tag == selection
        return Button {
            if selection != item.tag {
                Haptics.selection()
                selection = item.tag
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(selected
                                     ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xD6EEFF), Color(hex: 0x2C8DF4)],
                                                                    startPoint: .top, endPoint: .bottom))
                                     : AnyShapeStyle(Color(hex: 0x8E8E8E)))
                    .shadow(color: .black.opacity(0.6), radius: 0, y: -1)
                    .frame(height: 27)
                Text(item.title)
                    .font(.retroFixed(10, .bold))
                    .foregroundStyle(selected ? Color.white : Color(hex: 0x9A9A9A))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 45)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.08)],
                                             startPoint: .top, endPoint: .bottom))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var background: some View {
        ZStack(alignment: .top) {
            LinearGradient(stops: [
                .init(color: Color(hex: 0x3C3C3C), location: 0),
                .init(color: Color(hex: 0x1D1D1D), location: 0.5),
                .init(color: Color(hex: 0x060606), location: 0.5),
                .init(color: .black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
        }
    }
}

// MARK: - iOS 4 action sheet (UIActionSheet)

struct CommSheetButton {
    enum Role { case normal, destructive, cancel }
    var title: String
    var role: Role = .normal
    var action: () -> Void = {}
}

struct CommActionSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    var title: String?
    var buttons: [CommSheetButton]

    func body(content: Content) -> some View {
        content.overlay {
            ZStack(alignment: .bottom) {
                if isPresented {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { isPresented = false }
                        .transition(.opacity)
                    sheet
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeOut(duration: 0.25), value: isPresented)
        }
    }

    private var sheet: some View {
        VStack(spacing: 9) {
            if let title {
                Text(title)
                    .font(.retro(14))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 0, y: -1)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 2)
            }
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, b in
                Button {
                    SoundService.shared.play(.tock)
                    isPresented = false
                    b.action()
                } label: {
                    Text(b.title)
                        .font(.retro(18, .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(b.role == .normal ? Color(hex: 0x1E1E1E) : .white)
                        .shadow(color: b.role == .normal ? .white.opacity(0.8) : .black.opacity(0.5), radius: 0, y: b.role == .normal ? 1 : -1)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(buttonFill(b.role))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.55), lineWidth: 1))
                }
                .buttonStyle(PressDimStyle())
                .padding(.top, b.role == .cancel ? 6 : 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hex: 0x4E5767, opacity: 0.95), Color(hex: 0x1E2430, opacity: 0.97)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1)
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func buttonFill(_ role: CommSheetButton.Role) -> LinearGradient {
        let colors: [Color]
        switch role {
        case .normal: colors = [Color(hex: 0xFFFFFF), Color(hex: 0xD2D2D2)]
        case .destructive: colors = [Color(hex: 0xF0645A), Color(hex: 0xB3140B)]
        case .cancel: colors = [Color(hex: 0x6D7383), Color(hex: 0x2D3240)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

extension View {
    func commActionSheet(_ title: String? = nil, isPresented: Binding<Bool>, buttons: [CommSheetButton]) -> some View {
        modifier(CommActionSheetModifier(isPresented: isPresented, title: title, buttons: buttons))
    }
}

// MARK: - Phone numbers

nonisolated enum CommPhone {
    /// Only the characters a `tel:` URL can carry reliably: ASCII digits and a leading "+".
    static func dialable(_ raw: String) -> String {
        var out = ""
        for ch in raw {
            if ch.isASCII && ch.isNumber {
                out.append(ch)
            } else if ch == "+" && out.isEmpty {
                out.append(ch)
            }
        }
        return out
    }

    /// Normalized digits used to compare two numbers (KR +82 prefix folded to a leading 0).
    static func matchKey(_ raw: String) -> String {
        var digits = raw.filter { $0.isASCII && $0.isNumber }
        if digits.hasPrefix("82") && digits.count >= 11 {
            digits = "0" + digits.dropFirst(2)
        }
        return digits
    }

    /// Progressive formatting for the keypad display, following the device region (KR / NANP);
    /// other regions and anything containing * # + are shown as typed.
    static func format(_ raw: String, region: String? = Locale.current.region?.identifier) -> String {
        guard !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }) else { return raw }
        switch region ?? "KR" {
        case "KR": return formatKR(raw)
        case "US", "CA": return formatNANP(raw)
        default: return raw
        }
    }

    private static func slice(_ d: [Character], _ from: Int, _ to: Int? = nil) -> String {
        let end = min(to ?? d.count, d.count)
        guard from < end else { return "" }
        return String(d[from..<end])
    }

    static func formatKR(_ raw: String) -> String {
        let d = Array(raw)
        let n = d.count
        if raw.hasPrefix("02") {
            let rest = n - 2
            if rest <= 0 { return raw }
            if rest <= 3 { return "02-" + slice(d, 2) }
            if rest <= 7 { return "02-" + slice(d, 2, 5) + "-" + slice(d, 5) }
            if rest == 8 { return "02-" + slice(d, 2, 6) + "-" + slice(d, 6) }
            return raw
        }
        if raw.hasPrefix("0") {
            if n <= 3 { return raw }
            let rest = n - 3
            if rest <= 3 { return slice(d, 0, 3) + "-" + slice(d, 3) }
            if rest <= 7 { return slice(d, 0, 3) + "-" + slice(d, 3, 6) + "-" + slice(d, 6) }
            if rest == 8 { return slice(d, 0, 3) + "-" + slice(d, 3, 7) + "-" + slice(d, 7) }
            return raw
        }
        if (raw.hasPrefix("15") || raw.hasPrefix("16") || raw.hasPrefix("18")) && n > 4 && n <= 8 {
            return slice(d, 0, 4) + "-" + slice(d, 4)
        }
        return raw
    }

    static func formatNANP(_ raw: String) -> String {
        var digits = raw
        var prefix = ""
        if digits.hasPrefix("1") && digits.count > 1 {
            prefix = "1 "
            digits.removeFirst()
        }
        let d = Array(digits)
        let n = d.count
        if n <= 3 { return prefix + digits }
        if n <= 7 { return prefix + slice(d, 0, 3) + "-" + slice(d, 3) }
        if n <= 10 { return prefix + "(" + slice(d, 0, 3) + ") " + slice(d, 3, 6) + "-" + slice(d, 6) }
        return raw
    }
}

/// Opens system URLs (tel:, sms:, mailto:) — the only public way to place calls / hand off messages.
enum CommDialer {
    /// Places a real call through iOS. Returns false when the device can't make calls (e.g. Simulator, iPad).
    @discardableResult
    static func call(_ number: String, name: String? = nil) async -> Bool {
        let digits = CommPhone.dialable(number)
        guard !digits.isEmpty, let url = URL(string: "tel:" + digits) else { return false }
        let ok = await UIApplication.shared.open(url, options: [:])
        if ok { PhoneLocalStore.shared.logDial(number: digits, name: name) }
        return ok
    }

    @discardableResult
    static func openSMS(_ number: String) async -> Bool {
        let digits = CommPhone.dialable(number)
        guard !digits.isEmpty, let url = URL(string: "sms:" + digits) else { return false }
        return await UIApplication.shared.open(url, options: [:])
    }

    @discardableResult
    static func openMail(_ address: String) async -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed),
              !encoded.isEmpty, let url = URL(string: "mailto:" + encoded) else { return false }
        return await UIApplication.shared.open(url, options: [:])
    }

    @discardableResult
    static func openWeb(_ string: String) async -> Bool {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "https://" + s }
        guard let url = URL(string: s) else { return false }
        return await UIApplication.shared.open(url, options: [:])
    }
}

// MARK: - Section index (Hangul initial consonants + Latin letters)

nonisolated enum CommIndex {
    static let choseong: [String] = ["ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ",
                                     "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
    static let mergedDouble: [String: String] = ["ㄲ": "ㄱ", "ㄸ": "ㄷ", "ㅃ": "ㅂ", "ㅆ": "ㅅ", "ㅉ": "ㅈ"]
    static let korean: [String] = ["ㄱ", "ㄴ", "ㄷ", "ㄹ", "ㅁ", "ㅂ", "ㅅ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
    static let latin: [String] = (65...90).map { String(Character(Unicode.Scalar(UInt8($0)))) }

    /// Section key for a name: Hangul initial consonant (double consonants merged), A–Z, or "#".
    static func sectionKey(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scalar = trimmed.unicodeScalars.first else { return "#" }
        let v = scalar.value
        if v >= 0xAC00 && v <= 0xD7A3 {
            let c = choseong[Int((v - 0xAC00) / 588)]
            return mergedDouble[c] ?? c
        }
        if v >= 0x3131 && v <= 0x314E {
            let s = String(Character(scalar))
            let m = mergedDouble[s] ?? s
            return korean.contains(m) ? m : "#"
        }
        let folded = String(Character(scalar)).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).uppercased()
        if let f = folded.unicodeScalars.first, f.value >= 65 && f.value <= 90 { return String(Character(f)) }
        return "#"
    }

    /// Sort rank of a section key. Korean UI lists ㄱ–ㅎ first, English lists A–Z first; "#" is always last.
    static func rank(_ key: String, koreanFirst: Bool) -> Int {
        if let i = korean.firstIndex(of: key) { return (koreanFirst ? 0 : 100) + i }
        if let i = latin.firstIndex(of: key) { return (koreanFirst ? 100 : 0) + i }
        return 1000
    }
}

// MARK: - Small shared views

/// Two-column row used on detail pages (iOS 4 "label | value" cell).
struct CommDetailRow: View {
    @Environment(\.retroTheme) private var theme
    var label: String
    var value: String
    var valueColor: Color = .black

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.retro(13, .bold))
                .foregroundStyle(theme.detailText)
                .frame(width: 76, alignment: .trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.retro(15, .bold))
                .foregroundStyle(valueColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Embossed explanatory text placed directly on the pinstripe background.
struct CommNote: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.retro(14))
            .foregroundStyle(Color(hex: 0x4C566C))
            .embossed()
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
    }
}

/// Plain-list empty state (white background).
struct CommEmptyState: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 46))
                .foregroundStyle(Color(hex: 0xA9B0BC))
            Text(title)
                .font(.retro(19, .bold))
                .foregroundStyle(Color(hex: 0x6D7380))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.retro(14))
                .foregroundStyle(Color(hex: 0x8A909C))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
