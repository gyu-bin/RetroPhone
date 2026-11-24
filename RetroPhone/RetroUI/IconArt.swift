import SwiftUI

/// Original, code-drawn 2010-style icon artwork. Everything is vector (shapes, gradients and
/// SF Symbols glyphs), so icons stay sharp at any size. No Apple or third-party brand artwork
/// is reproduced: third-party apps get generic metaphors (e.g. a CRT TV for a video app).
enum IconArt: String, Codable, CaseIterable, Identifiable {
    // Built-in apps
    case phone, messages, contacts, photos, camera, music, browser, notes
    case calendar, weather, calculator, clock, maps, voiceMemos, settings
    // External app metaphors
    case chatBubbleYellow, instantCamera, crtTV, searchGreen, mapGreen, mapPinYellow
    case wallet, robot, envelope, filmReel, shoppingBag, vinyl
    // Extra choices for user customization
    case generic, game, book, heart, star, chart, gift, globe
    // Generic metaphors for the expanded app catalog (glossy tile + symbol)
    case chatGreen, chatBlue, chatPurple, chatDark, musicGreen, musicPurple, playRed
    case bankYellow, bankBlue, bankNavy, payYellow, carrot, delivery, taxi, navigation, plane, bed, house
    case cart, tshirt, webtoon, docs, briefcase, videoCall, mailBlue, checklist, folderBlue, layers
    case podcast, tvDark, radar, appStore, walletDark, books, translate, news, coffee, pin, people
    case searchBlue, cloudDrive, ticket, sparkle, bolt, atSign

    var id: String { rawValue }
}

/// Icon background + artwork, clipped to the classic rounded square, with the iOS-style gloss.
struct RetroIconView: View {
    @Environment(\.retroTheme) private var theme
    var art: IconArt
    var size: CGFloat
    var customImage: UIImage? = nil
    var gloss: Bool = true

    static func cornerRadius(_ size: CGFloat) -> CGFloat {
        size * (SettingsStore.shared.value.themeEra == .ios7 ? 0.225 : 0.175)
    }

    var body: some View {
        if theme.isFlat { flatBody } else { classicBody }
    }

    /// iOS 7: flat art, rounder corners, no gloss, border or drop shadow.
    private var flatBody: some View {
        ZStack {
            if let customImage {
                Image(uiImage: customImage).resizable().scaledToFill()
            } else {
                FlatIconArtwork(art: art, s: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius(size), style: .continuous))
        .drawingGroup()
        .accessibilityHidden(true)
    }

    @ViewBuilder private var classicBody: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius(size), style: .continuous)
        ZStack {
            if let customImage {
                Image(uiImage: customImage).resizable().scaledToFill()
            } else {
                IconArtwork(art: art, s: size)
            }
            if gloss { GlossOverlay() }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.black.opacity(0.25), lineWidth: max(0.5, size / 120)))
        .drawingGroup()
        .shadow(color: .black.opacity(0.55), radius: size * 0.04, x: 0, y: size * 0.035)
        .accessibilityHidden(true)
    }
}

/// The signature iOS 1–6 icon shine: a bright elliptical highlight over the top half.
struct GlossOverlay: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.62), .white.opacity(0.12)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: w * 1.6, height: h * 1.0)
                .position(x: w / 2, y: h * 0.0)
                .blendMode(.screen)
        }
        .allowsHitTesting(false)
    }
}

private func vgrad(_ top: UInt32, _ bottom: UInt32) -> LinearGradient {
    LinearGradient(colors: [Color(hex: top), Color(hex: bottom)], startPoint: .top, endPoint: .bottom)
}

/// Renders a glyph (SF Symbol) with a vertical gradient and a soft embossed shadow.
private struct Glyph: View {
    var name: String
    var size: CGFloat
    var colors: [Color] = [.white, Color(hex: 0xDCDCDC)]
    var shadow: Color = .black.opacity(0.45)
    var body: some View {
        Image(systemName: name)
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .shadow(color: shadow, radius: size * 0.03, x: 0, y: size * 0.04)
    }
}

struct IconArtwork: View {
    var art: IconArt
    var s: CGFloat

    var body: some View {
        switch art {
        case .phone:
            ZStack { vgrad(0x86E065, 0x23901A); Glyph(name: "phone.fill", size: s * 0.56, shadow: Color(hex: 0x0D4A08).opacity(0.7)) }
        case .messages:
            ZStack {
                vgrad(0x9BE878, 0x2E9F24)
                Glyph(name: "bubble.left.fill", size: s * 0.62, shadow: Color(hex: 0x0D4A08).opacity(0.7))
            }
        case .contacts: contacts
        case .photos: photos
        case .camera: camera
        case .music:
            ZStack { vgrad(0xFFB955, 0xEC5A0C); Glyph(name: "music.note", size: s * 0.56, shadow: Color(hex: 0x7A2600).opacity(0.7)) }
        case .browser: compass
        case .notes: notes
        case .calendar: CalendarIconFace(s: s)
        case .weather: weather
        case .calculator: calculator
        case .clock: clock
        case .maps: map(pin: Color(hex: 0xE0281E))
        case .voiceMemos: microphone
        case .settings: settings
        case .chatBubbleYellow:
            ZStack {
                vgrad(0xFFEC5C, 0xF2BF00)
                Glyph(name: "ellipsis.bubble.fill", size: s * 0.6, colors: [Color(hex: 0x5A3A22), Color(hex: 0x3A2414)],
                      shadow: .white.opacity(0.5))
            }
        case .instantCamera: instantCamera
        case .crtTV: crt
        case .searchGreen:
            ZStack { vgrad(0x74DA6E, 0x139A30); Glyph(name: "magnifyingglass", size: s * 0.52, shadow: Color(hex: 0x0A4A14).opacity(0.7)) }
        case .mapGreen: map(pin: Color(hex: 0x1DB33E))
        case .mapPinYellow: map(pin: Color(hex: 0xF5C400))
        case .wallet:
            ZStack { vgrad(0x5CA4FF, 0x1050CF); Glyph(name: "creditcard.fill", size: s * 0.56, shadow: Color(hex: 0x05235E).opacity(0.7)) }
        case .robot: terminal
        case .envelope:
            ZStack {
                vgrad(0xFAFAFA, 0xC9C9C9)
                Glyph(name: "envelope.fill", size: s * 0.62, colors: [Color(hex: 0xF0554A), Color(hex: 0xB8231A)], shadow: .black.opacity(0.35))
            }
        case .filmReel:
            ZStack {
                vgrad(0x3A0A0A, 0x0E0202)
                Glyph(name: "film", size: s * 0.6, colors: [Color(hex: 0xFF5A5A), Color(hex: 0xB0141A)], shadow: .black)
            }
        case .shoppingBag:
            ZStack {
                vgrad(0xF6F1E8, 0xD7CBB4)
                Glyph(name: "bag.fill", size: s * 0.58, colors: [Color(hex: 0xD8A866), Color(hex: 0x9C6A2E)], shadow: .black.opacity(0.35))
            }
        case .vinyl: vinyl
        case .generic:
            ZStack { vgrad(0x9AB0CF, 0x4C6489); Glyph(name: "app.dashed", size: s * 0.5) }
        case .game:
            ZStack { vgrad(0x8A6CE0, 0x40229A); Glyph(name: "gamecontroller.fill", size: s * 0.62) }
        case .book:
            ZStack { vgrad(0xC98A4E, 0x7A4515); Glyph(name: "book.closed.fill", size: s * 0.52, colors: [Color(hex: 0xFFF6E0), Color(hex: 0xE2D2B0)]) }
        case .heart:
            ZStack { vgrad(0xFFFFFF, 0xDADADA); Glyph(name: "heart.fill", size: s * 0.56, colors: [Color(hex: 0xFF6680), Color(hex: 0xD8143A)], shadow: .black.opacity(0.3)) }
        case .star:
            ZStack { vgrad(0x5B6E8E, 0x1C2A44); Glyph(name: "star.fill", size: s * 0.58, colors: [Color(hex: 0xFFE680), Color(hex: 0xF0A800)]) }
        case .chart:
            ZStack { vgrad(0x2F2F2F, 0x0A0A0A); Glyph(name: "chart.line.uptrend.xyaxis", size: s * 0.56, colors: [Color(hex: 0x9CFF9C), Color(hex: 0x2FCB45)]) }
        case .gift:
            ZStack { vgrad(0xFF7272, 0xC0141E); Glyph(name: "gift.fill", size: s * 0.56) }
        case .globe:
            ZStack { vgrad(0x67C0FF, 0x0D5FC9); Glyph(name: "globe.asia.australia.fill", size: s * 0.6, colors: [Color(hex: 0xC8F5B8), Color(hex: 0x5FBF45)]) }
        default:
            if let t = SymbolTile.table[art] {
                ZStack {
                    vgrad(t.top, t.bottom)
                    Glyph(name: t.symbol, size: s * t.scale,
                          colors: [Color(hex: t.glyphTop), Color(hex: t.glyphBottom)],
                          shadow: .black.opacity(t.glyphTop == 0xFFFFFF ? 0.45 : 0.25))
                }
            } else {
                ZStack { vgrad(0x9AB0CF, 0x4C6489); Glyph(name: "app.dashed", size: s * 0.5) }
            }
        }
    }

    // MARK: Hand-drawn pieces

    private var contacts: some View {
        ZStack(alignment: .leading) {
            vgrad(0xB07F50, 0x6A4220)
            // Pages on the right edge
            HStack(spacing: 0) {
                Spacer()
                VStack(spacing: s * 0.01) {
                    ForEach([0xE84A3C, 0xF0A030, 0x3C9CE8, 0x46B04A], id: \.self) { c in
                        Rectangle().fill(Color(hex: UInt32(c))).frame(width: s * 0.07, height: s * 0.12)
                    }
                }.padding(.trailing, s * 0.02)
            }
            // Spine
            LinearGradient(colors: [Color(hex: 0x4A2A10), Color(hex: 0x7A5230), Color(hex: 0x4A2A10)], startPoint: .leading, endPoint: .trailing)
                .frame(width: s * 0.16)
            Circle().fill(vgrad(0xF3E2C4, 0xC9AE84))
                .frame(width: s * 0.5).overlay(Glyph(name: "person.fill", size: s * 0.32, colors: [Color(hex: 0x7A5A3A), Color(hex: 0x4A3220)], shadow: .white.opacity(0.4)))
                .offset(x: s * 0.22)
        }
    }

    private var photos: some View {
        ZStack {
            vgrad(0x7CC4F8, 0x2C7DD0)
            // Stem and leaf
            Capsule().fill(Color(hex: 0x3E9A2A)).frame(width: s * 0.06, height: s * 0.5).offset(y: s * 0.3)
            Ellipse().fill(Color(hex: 0x4FB43A)).frame(width: s * 0.22, height: s * 0.1).rotationEffect(.degrees(-30)).offset(x: s * 0.1, y: s * 0.32)
            // Petals
            ForEach(0..<12, id: \.self) { i in
                Ellipse()
                    .fill(LinearGradient(colors: [Color(hex: 0xFFE24A), Color(hex: 0xF5A300)], startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.13, height: s * 0.3)
                    .offset(y: -s * 0.17)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            .offset(y: -s * 0.04)
            Circle().fill(RadialGradient(colors: [Color(hex: 0x8A5A20), Color(hex: 0x4A2A08)], center: .center, startRadius: 0, endRadius: s * 0.12))
                .frame(width: s * 0.22).offset(y: -s * 0.04)
        }
    }

    private var camera: some View {
        ZStack {
            vgrad(0xE6E6E6, 0x8C8C8C)
            Circle().fill(vgrad(0x4A4A4A, 0x0A0A0A)).frame(width: s * 0.72)
            Circle().stroke(vgrad(0xBDBDBD, 0x5A5A5A), lineWidth: s * 0.04).frame(width: s * 0.6)
            Circle().fill(RadialGradient(colors: [Color(hex: 0x5A6CC8), Color(hex: 0x1A1A40), .black],
                                         center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: s * 0.24))
                .frame(width: s * 0.44)
            Circle().fill(.white.opacity(0.8)).frame(width: s * 0.08).offset(x: -s * 0.07, y: -s * 0.08)
        }
    }

    private var compass: some View {
        ZStack {
            vgrad(0x8ED4FF, 0x1A6AD6)
            Circle().fill(vgrad(0xFFFFFF, 0xE2E8EE)).frame(width: s * 0.74)
                .shadow(color: .black.opacity(0.35), radius: s * 0.02, y: s * 0.02)
            ForEach(0..<24, id: \.self) { i in
                Rectangle().fill(Color(hex: 0x6A7A8A))
                    .frame(width: s * 0.008, height: i % 6 == 0 ? s * 0.07 : s * 0.035)
                    .offset(y: -s * 0.32)
                    .rotationEffect(.degrees(Double(i) * 15))
            }
            // Needle
            VStack(spacing: 0) {
                Triangle().fill(Color(hex: 0xE53B2C)).frame(width: s * 0.1, height: s * 0.28)
                Triangle().fill(Color(hex: 0xEDEDED)).frame(width: s * 0.1, height: s * 0.28).rotationEffect(.degrees(180))
            }
            .shadow(color: .black.opacity(0.4), radius: s * 0.01, y: s * 0.01)
            .rotationEffect(.degrees(45))
            Circle().fill(Color(hex: 0x555555)).frame(width: s * 0.05)
        }
    }

    private var notes: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0xFFF6B5), Color(hex: 0xF5DB6A)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: s * 0.1) {
                ForEach(0..<6, id: \.self) { _ in Rectangle().fill(Color(hex: 0xC8A957).opacity(0.7)).frame(height: max(0.5, s * 0.012)) }
            }
            .padding(.top, s * 0.34)
            Rectangle().fill(Color(hex: 0xE05050).opacity(0.6)).frame(width: max(0.5, s * 0.012)).offset(x: -s * 0.3)
            // Leather binding
            ZStack(alignment: .bottom) {
                vgrad(0x9A6634, 0x5E3712)
                Rectangle().stroke(style: StrokeStyle(lineWidth: max(0.5, s * 0.012), dash: [s * 0.03, s * 0.02]))
                    .foregroundStyle(Color(hex: 0xE8C890).opacity(0.8))
                    .frame(height: 0.1).padding(.horizontal, -2).offset(y: -s * 0.05)
            }
            .frame(height: s * 0.24)
            .shadow(color: .black.opacity(0.4), radius: s * 0.02, y: s * 0.02)
        }
    }

    private var weather: some View {
        ZStack {
            vgrad(0x5EB6F7, 0x1A58C2)
            Circle().fill(RadialGradient(colors: [Color(hex: 0xFFF6A0), Color(hex: 0xFFC400)], center: .center, startRadius: 0, endRadius: s * 0.2))
                .frame(width: s * 0.4)
                .shadow(color: Color(hex: 0xFFD040).opacity(0.9), radius: s * 0.06)
                .offset(x: -s * 0.1, y: -s * 0.1)
            Glyph(name: "cloud.fill", size: s * 0.56, colors: [.white, Color(hex: 0xD6E4F0)], shadow: Color(hex: 0x0A2A6A).opacity(0.5))
                .offset(x: s * 0.08, y: s * 0.1)
        }
    }

    private var calculator: some View {
        ZStack {
            vgrad(0x5A5A5A, 0x232323)
            let k = s * 0.3
            VStack(spacing: s * 0.06) {
                HStack(spacing: s * 0.06) {
                    key("+", Color(hex: 0x8A8A8A), Color(hex: 0x4A4A4A), k)
                    key("−", Color(hex: 0x8A8A8A), Color(hex: 0x4A4A4A), k)
                }
                HStack(spacing: s * 0.06) {
                    key("×", Color(hex: 0x8A8A8A), Color(hex: 0x4A4A4A), k)
                    key("=", Color(hex: 0xFFAA40), Color(hex: 0xE06000), k)
                }
            }
        }
    }

    private func key(_ t: String, _ top: Color, _ bottom: Color, _ k: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: k * 0.2)
            .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            .frame(width: k, height: k)
            .overlay(Text(t).font(.system(size: k * 0.7, weight: .bold)).foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 0, y: -1))
            .shadow(color: .black.opacity(0.6), radius: k * 0.04, y: k * 0.05)
    }

    private var clock: some View {
        ZStack {
            Color.black
            Circle().fill(vgrad(0xFFFFFF, 0xDADADA)).frame(width: s * 0.82)
            ForEach(0..<12, id: \.self) { i in
                Rectangle().fill(Color.black).frame(width: s * 0.022, height: s * 0.07)
                    .offset(y: -s * 0.33).rotationEffect(.degrees(Double(i) * 30))
            }
            Capsule().fill(Color.black).frame(width: s * 0.045, height: s * 0.24).offset(y: -s * 0.1).rotationEffect(.degrees(-60))
            Capsule().fill(Color.black).frame(width: s * 0.035, height: s * 0.34).offset(y: -s * 0.15).rotationEffect(.degrees(60))
            Capsule().fill(Color(hex: 0xE02020)).frame(width: s * 0.014, height: s * 0.36).offset(y: -s * 0.14).rotationEffect(.degrees(170))
            Circle().fill(Color(hex: 0xE02020)).frame(width: s * 0.05)
        }
    }

    private func map(pin: Color) -> some View {
        ZStack {
            Color(hex: 0xEFE7D2)
            Path { p in
                p.move(to: CGPoint(x: 0, y: s * 0.62)); p.addCurve(to: CGPoint(x: s, y: s * 0.48),
                    control1: CGPoint(x: s * 0.35, y: s * 0.5), control2: CGPoint(x: s * 0.6, y: s * 0.7))
            }.stroke(Color(hex: 0x7FB7E8), lineWidth: s * 0.09)
            Rectangle().fill(Color(hex: 0xBFDDA0)).frame(width: s * 0.35, height: s * 0.28).position(x: s * 0.22, y: s * 0.22)
            Path { p in
                p.move(to: CGPoint(x: s * 0.62, y: 0)); p.addLine(to: CGPoint(x: s * 0.5, y: s))
                p.move(to: CGPoint(x: 0, y: s * 0.38)); p.addLine(to: CGPoint(x: s, y: s * 0.28))
            }.stroke(Color.white, lineWidth: s * 0.07)
            Path { p in
                p.move(to: CGPoint(x: s * 0.62, y: 0)); p.addLine(to: CGPoint(x: s * 0.5, y: s))
            }.stroke(Color(hex: 0xF5C94A), lineWidth: s * 0.035)
            // Pin
            VStack(spacing: 0) {
                Circle().fill(RadialGradient(colors: [pin.opacity(0.6), pin], center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: s * 0.1))
                    .frame(width: s * 0.2)
                    .overlay(Circle().fill(.white.opacity(0.7)).frame(width: s * 0.05).offset(x: -s * 0.03, y: -s * 0.03))
                Rectangle().fill(Color(hex: 0x8A8A8A)).frame(width: s * 0.025, height: s * 0.16)
            }
            .shadow(color: .black.opacity(0.4), radius: s * 0.02, x: s * 0.02, y: s * 0.02)
            .offset(x: s * 0.12, y: -s * 0.08)
        }
    }

    private var microphone: some View {
        ZStack {
            vgrad(0x4A4A4A, 0x0E0E0E)
            VStack(spacing: 0) {
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xF2F2F2), Color(hex: 0x8A8A8A), Color(hex: 0xD8D8D8)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: s * 0.3, height: s * 0.46)
                    .overlay(
                        VStack(spacing: s * 0.025) {
                            ForEach(0..<6, id: \.self) { _ in Rectangle().fill(Color.black.opacity(0.35)).frame(width: s * 0.2, height: max(0.5, s * 0.012)) }
                        }.padding(.bottom, s * 0.12)
                    )
                Rectangle().fill(Color(hex: 0x9A9A9A)).frame(width: s * 0.04, height: s * 0.1)
                Capsule().fill(Color(hex: 0x9A9A9A)).frame(width: s * 0.28, height: s * 0.04)
            }
        }
    }

    private var settings: some View {
        ZStack {
            vgrad(0xA6ABB2, 0x50555C)
            let metal = [Color(hex: 0xF4F4F4), Color(hex: 0x9EA2A8), Color(hex: 0x6C7076)]
            Glyph(name: "gearshape.fill", size: s * 0.72, colors: metal, shadow: .black.opacity(0.6))
            Circle().fill(vgrad(0x5A5E64, 0x8A8E94)).frame(width: s * 0.2)
            Glyph(name: "gearshape.fill", size: s * 0.3, colors: metal, shadow: .black.opacity(0.6))
                .offset(x: s * 0.28, y: s * 0.28)
        }
    }

    private var instantCamera: some View {
        VStack(spacing: 0) {
            ZStack {
                vgrad(0xEFE3C8, 0xCDB98F)
                HStack {
                    RoundedRectangle(cornerRadius: s * 0.03).fill(Color(hex: 0x222222)).frame(width: s * 0.18, height: s * 0.12)
                    Spacer()
                    Circle().fill(vgrad(0xFF6A5A, 0xC8261A)).frame(width: s * 0.12)
                }.padding(.horizontal, s * 0.12)
            }.frame(height: s * 0.38)
            vgrad(0x7A5634, 0x4A3018)
        }
        .overlay(
            ZStack {
                Circle().fill(vgrad(0x3A3A3A, 0x0A0A0A)).frame(width: s * 0.48)
                Circle().stroke(Color(hex: 0x9A9A9A), lineWidth: s * 0.025).frame(width: s * 0.4)
                Circle().fill(RadialGradient(colors: [Color(hex: 0x4A64B8), .black], center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: s * 0.15))
                    .frame(width: s * 0.3)
                Circle().fill(.white.opacity(0.75)).frame(width: s * 0.06).offset(x: -s * 0.05, y: -s * 0.05)
            }.offset(y: s * 0.08)
        )
    }

    private var crt: some View {
        ZStack {
            vgrad(0x7A4E2C, 0x3E220E)
            HStack(spacing: s * 0.05) {
                RoundedRectangle(cornerRadius: s * 0.1)
                    .fill(RadialGradient(colors: [Color(hex: 0x8AA6C0), Color(hex: 0x25384A)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: s * 0.4))
                    .frame(width: s * 0.6, height: s * 0.5)
                    .overlay(Glyph(name: "play.fill", size: s * 0.2, colors: [Color(hex: 0xFF5050), Color(hex: 0xC01010)], shadow: .black.opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: s * 0.1).stroke(Color.black.opacity(0.6), lineWidth: s * 0.02))
                VStack(spacing: s * 0.06) {
                    Circle().fill(vgrad(0xDADADA, 0x7A7A7A)).frame(width: s * 0.1)
                    Circle().fill(vgrad(0xDADADA, 0x7A7A7A)).frame(width: s * 0.1)
                    VStack(spacing: s * 0.015) {
                        ForEach(0..<3, id: \.self) { _ in Rectangle().fill(Color.black.opacity(0.5)).frame(width: s * 0.1, height: max(0.5, s * 0.012)) }
                    }
                }
            }
        }
    }

    private var terminal: some View {
        ZStack {
            vgrad(0x3C5A5A, 0x0E2020)
            RoundedRectangle(cornerRadius: s * 0.08)
                .fill(RadialGradient(colors: [Color(hex: 0x0C2A14), .black], center: .center, startRadius: 0, endRadius: s * 0.4))
                .frame(width: s * 0.74, height: s * 0.6)
                .overlay(RoundedRectangle(cornerRadius: s * 0.08).stroke(Color(hex: 0x8A9A9A), lineWidth: s * 0.03))
                .overlay(
                    Text(">_").font(.system(size: s * 0.26, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x5CFF7A)).shadow(color: Color(hex: 0x5CFF7A), radius: s * 0.03)
                )
        }
    }

    private var vinyl: some View {
        ZStack {
            vgrad(0x3A3A3A, 0x101010)
            Circle().fill(Color(hex: 0x0A0A0A)).frame(width: s * 0.84)
            ForEach(1..<6, id: \.self) { i in
                Circle().stroke(Color.white.opacity(0.08), lineWidth: max(0.5, s * 0.008)).frame(width: s * (0.3 + CGFloat(i) * 0.1))
            }
            AngularGradient(colors: [.clear, .white.opacity(0.18), .clear, .white.opacity(0.12), .clear], center: .center)
                .clipShape(Circle()).frame(width: s * 0.84)
            Circle().fill(vgrad(0x6BEA8E, 0x16A44A)).frame(width: s * 0.3)
            Circle().fill(Color.black).frame(width: s * 0.04)
        }
    }
}

/// The calendar icon shows the real current date (red header + day number).
struct CalendarIconFace: View {
    var s: CGFloat
    var body: some View {
        let now = ClockTicker.shared.now
        VStack(spacing: 0) {
            ZStack {
                vgrad(0xEF5A4C, 0xB8180E)
                Text(RetroFormat.date(now, template: "EEE"))
                    .font(.custom("Helvetica-Bold", fixedSize: s * 0.17))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 0, y: -1)
            }
            .frame(height: s * 0.3)
            ZStack {
                vgrad(0xFFFFFF, 0xE4E4E4)
                Text("\(Calendar.current.component(.day, from: now))")
                    .font(.custom("Helvetica-Bold", fixedSize: s * 0.5))
                    .foregroundStyle(Color(hex: 0x1A1A1A))
                    .offset(y: s * 0.01)
            }
        }
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

/// Table-driven glossy tiles: gradient background + SF Symbol glyph. Used for the large app catalog so
/// every third-party app gets a consistent 2010-style metaphor without brand logos.
struct SymbolTile {
    var top: UInt32
    var bottom: UInt32
    var symbol: String
    var glyphTop: UInt32 = 0xFFFFFF
    var glyphBottom: UInt32 = 0xDCDCDC
    var scale: CGFloat = 0.56

    static let table: [IconArt: SymbolTile] = [
        .chatGreen: .init(top: 0x7CE07A, bottom: 0x1F9E3A, symbol: "bubble.left.fill"),
        .chatBlue: .init(top: 0x6FC2FF, bottom: 0x1A6FD8, symbol: "paperplane.fill"),
        .chatPurple: .init(top: 0x9D8CFF, bottom: 0x4A3AC8, symbol: "bubble.left.and.bubble.right.fill"),
        .chatDark: .init(top: 0x4A4A4A, bottom: 0x111111, symbol: "at", scale: 0.5),
        .musicGreen: .init(top: 0x6BEA7A, bottom: 0x10A43A, symbol: "music.note.list"),
        .musicPurple: .init(top: 0xC88CFF, bottom: 0x6A2AC8, symbol: "music.quarternote.3"),
        .playRed: .init(top: 0xFF6A5A, bottom: 0xC8160B, symbol: "play.circle.fill", scale: 0.6),
        .bankYellow: .init(top: 0xFFE45C, bottom: 0xF2B800, symbol: "building.columns.fill", glyphTop: 0x4A3418, glyphBottom: 0x2A1C08),
        .bankBlue: .init(top: 0x5C9CFF, bottom: 0x1448C8, symbol: "building.columns.fill"),
        .bankNavy: .init(top: 0x4A5C8A, bottom: 0x1A2448, symbol: "wonsign.circle.fill", glyphTop: 0xFFE28A, glyphBottom: 0xE8B830),
        .payYellow: .init(top: 0xFFE45C, bottom: 0xF2B800, symbol: "creditcard.fill", glyphTop: 0x4A3418, glyphBottom: 0x2A1C08),
        .carrot: .init(top: 0xFFA25C, bottom: 0xF06A10, symbol: "carrot.fill"),
        .delivery: .init(top: 0x5CE8D8, bottom: 0x10B0A0, symbol: "scooter"),
        .taxi: .init(top: 0xFFDC4A, bottom: 0xE8A800, symbol: "car.fill", glyphTop: 0x2A2A2A, glyphBottom: 0x111111),
        .navigation: .init(top: 0x6CB4FF, bottom: 0x1858D8, symbol: "location.north.circle.fill", scale: 0.6),
        .plane: .init(top: 0xFF7A8A, bottom: 0xD8243C, symbol: "airplane"),
        .bed: .init(top: 0xFF7AB0, bottom: 0xD8246A, symbol: "bed.double.fill"),
        .house: .init(top: 0xFFC25C, bottom: 0xF08A10, symbol: "house.fill"),
        .cart: .init(top: 0xFF6A6A, bottom: 0xC8141E, symbol: "cart.fill"),
        .tshirt: .init(top: 0x5A5A5A, bottom: 0x141414, symbol: "tshirt.fill"),
        .webtoon: .init(top: 0x6CE87A, bottom: 0x10A43A, symbol: "book.pages.fill"),
        .docs: .init(top: 0xFAFAFA, bottom: 0xD2D2D2, symbol: "doc.text.fill", glyphTop: 0x3A3A3A, glyphBottom: 0x111111),
        .briefcase: .init(top: 0x8A6CE0, bottom: 0x40229A, symbol: "briefcase.fill"),
        .videoCall: .init(top: 0x7CE07A, bottom: 0x1F9E3A, symbol: "video.fill"),
        .mailBlue: .init(top: 0x7CC4FF, bottom: 0x1A6AD8, symbol: "envelope.fill"),
        .checklist: .init(top: 0xFAFAFA, bottom: 0xD8D8D8, symbol: "checklist", glyphTop: 0xF06A10, glyphBottom: 0xC84A00),
        .folderBlue: .init(top: 0xFAFAFA, bottom: 0xD8D8D8, symbol: "folder.fill", glyphTop: 0x5CA8FF, glyphBottom: 0x1A6AD8),
        .layers: .init(top: 0x7A8CFF, bottom: 0xD84AC8, symbol: "square.stack.3d.up.fill"),
        .podcast: .init(top: 0xC86CFF, bottom: 0x7A1AD8, symbol: "mic.fill"),
        .tvDark: .init(top: 0x3A3A3A, bottom: 0x0A0A0A, symbol: "tv.fill"),
        .radar: .init(top: 0x7CE07A, bottom: 0x1F9E3A, symbol: "dot.radiowaves.left.and.right"),
        .appStore: .init(top: 0x6CC4FF, bottom: 0x1A6AD8, symbol: "square.and.arrow.down.fill"),
        .walletDark: .init(top: 0x3A3A3A, bottom: 0x0A0A0A, symbol: "wallet.bifold.fill", glyphTop: 0xFFD27A, glyphBottom: 0xE89A20),
        .books: .init(top: 0xFFA84A, bottom: 0xE86A00, symbol: "book.fill"),
        .translate: .init(top: 0x5CA8FF, bottom: 0x1448C8, symbol: "character.bubble.fill"),
        .news: .init(top: 0xFAFAFA, bottom: 0xD8D8D8, symbol: "newspaper.fill", glyphTop: 0x3A3A3A, glyphBottom: 0x111111),
        .coffee: .init(top: 0x3ABA6A, bottom: 0x0A6A3A, symbol: "cup.and.saucer.fill"),
        .pin: .init(top: 0xFF5A5A, bottom: 0xC8101A, symbol: "pin.fill"),
        .people: .init(top: 0x5C8CFF, bottom: 0x1A48C8, symbol: "person.2.fill"),
        .searchBlue: .init(top: 0xFAFAFA, bottom: 0xD8D8D8, symbol: "magnifyingglass", glyphTop: 0x3A86FF, glyphBottom: 0x1448C8),
        .cloudDrive: .init(top: 0xFAFAFA, bottom: 0xD8D8D8, symbol: "externaldrive.fill.badge.icloud", glyphTop: 0x3ABA6A, glyphBottom: 0x1A8A3A),
        .ticket: .init(top: 0xFF8A5C, bottom: 0xE84A10, symbol: "ticket.fill"),
        .sparkle: .init(top: 0x2A2A3A, bottom: 0x0A0A14, symbol: "sparkles", glyphTop: 0xB8E0FF, glyphBottom: 0x6AA8FF),
        .bolt: .init(top: 0xFFE45C, bottom: 0xF2B800, symbol: "bolt.fill", glyphTop: 0x3A2A10, glyphBottom: 0x1A1408),
        .atSign: .init(top: 0x3A3A3A, bottom: 0x0A0A0A, symbol: "at.circle.fill"),
    ]
}

// MARK: - iOS 7 (flat) artwork

/// Flat, iOS 7-era artwork for the built-in apps: bright gradients, thin white glyphs, no gloss.
/// Original vector drawings (shapes + SF Symbols), like the classic set.
struct FlatIconArtwork: View {
    var art: IconArt
    var s: CGFloat

    static let flatArts: Set<IconArt> = [.phone, .messages, .contacts, .photos, .camera, .music, .browser, .notes,
                                         .calendar, .weather, .calculator, .clock, .maps, .voiceMemos, .settings]

    private func grad(_ top: UInt32, _ bottom: UInt32) -> LinearGradient {
        LinearGradient(colors: [Color(hex: top), Color(hex: bottom)], startPoint: .top, endPoint: .bottom)
    }

    private func glyph(_ name: String, _ scale: CGFloat, _ color: Color = .white, weight: Font.Weight = .regular) -> some View {
        Image(systemName: name).font(.system(size: s * scale, weight: weight)).foregroundStyle(color)
    }

    var body: some View {
        ZStack {
            switch art {
            case .phone:
                grad(0x87FC70, 0x0BD318)
                glyph("phone.fill", 0.5)
            case .messages:
                grad(0x87FC70, 0x0BD318)
                glyph("message.fill", 0.52)
            case .contacts:
                grad(0xF7F7F9, 0xD6D6DB)
                glyph("person.crop.circle.fill", 0.62, Color(hex: 0x8E8E93))
                VStack(spacing: s * 0.03) {
                    ForEach([0xFF3B30, 0xFF9500, 0x4CD964, 0x007AFF], id: \.self) { c in
                        Rectangle().fill(Color(hex: UInt32(c))).frame(width: s * 0.06, height: s * 0.12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            case .photos:
                Color.white
                ForEach(0..<8, id: \.self) { i in
                    Capsule()
                        .fill(Color(hue: Double(i) / 8, saturation: 0.75, brightness: 1).opacity(0.78))
                        .frame(width: s * 0.2, height: s * 0.38)
                        .offset(y: -s * 0.16)
                        .rotationEffect(.degrees(Double(i) * 45))
                        .blendMode(.multiply)
                }
            case .camera:
                grad(0xDBDDDE, 0x898C90)
                glyph("camera.fill", 0.46, Color(hex: 0x2C2C2E))
            case .music:
                grad(0xFF5E3A, 0xFF2A68)
                glyph("music.note", 0.5)
            case .browser:
                Color.white
                Circle().fill(grad(0x1AD6FD, 0x1D62F0)).frame(width: s * 0.78, height: s * 0.78)
                Circle().stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: s * 0.02, dash: [s * 0.012, s * 0.04]))
                    .frame(width: s * 0.66, height: s * 0.66)
                CompassNeedle().fill(Color(hex: 0xFF3B30)).frame(width: s * 0.1, height: s * 0.56).rotationEffect(.degrees(45))
                CompassNeedle().fill(Color.white).frame(width: s * 0.1, height: s * 0.56).rotationEffect(.degrees(225))
            case .notes:
                Color.white
                VStack(spacing: 0) {
                    grad(0xFFE57A, 0xFFCC00).frame(height: s * 0.24)
                    VStack(spacing: s * 0.12) {
                        ForEach(0..<5, id: \.self) { _ in Rectangle().fill(Color(hex: 0xD1D1D6)).frame(height: max(0.5, s * 0.012)) }
                    }
                    .padding(.top, s * 0.1)
                    Spacer(minLength: 0)
                }
            case .calendar:
                Color.white
                let now = Date()
                VStack(spacing: -s * 0.04) {
                    Text(RetroFormat.date(now, template: "EEEE"))
                        .font(.neue(s * 0.15)).foregroundStyle(Color(hex: 0xFF3B30))
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text("\(Calendar.current.component(.day, from: now))")
                        .font(.neue(s * 0.56, .ultraLight)).foregroundStyle(.black)
                }
                .padding(.horizontal, s * 0.06)
            case .weather:
                grad(0x1D77EF, 0x81F3FD)
                Circle().fill(Color(hex: 0xFFD60A)).frame(width: s * 0.34, height: s * 0.34).offset(x: -s * 0.1, y: -s * 0.1)
                glyph("cloud.fill", 0.46).offset(x: s * 0.06, y: s * 0.08)
            case .calculator:
                grad(0xDBDDDE, 0x898C90)
                let cell = s * 0.3
                VStack(spacing: s * 0.06) {
                    HStack(spacing: s * 0.06) { calcKey("plus", cell, Color(hex: 0x3A3A3C)); calcKey("minus", cell, Color(hex: 0x3A3A3C)) }
                    HStack(spacing: s * 0.06) { calcKey("multiply", cell, Color(hex: 0x3A3A3C)); calcKey("equal", cell, Color(hex: 0xFF9500)) }
                }
            case .clock:
                Color.black
                Circle().fill(Color.white).frame(width: s * 0.82, height: s * 0.82)
                ForEach(0..<12, id: \.self) { i in
                    Rectangle().fill(Color.black).frame(width: max(0.7, s * 0.018), height: s * 0.06)
                        .offset(y: -s * 0.34).rotationEffect(.degrees(Double(i) * 30))
                }
                Capsule().fill(Color.black).frame(width: s * 0.035, height: s * 0.24).offset(y: -s * 0.1).rotationEffect(.degrees(-60))
                Capsule().fill(Color.black).frame(width: s * 0.03, height: s * 0.32).offset(y: -s * 0.14).rotationEffect(.degrees(60))
                Capsule().fill(Color(hex: 0xFF3B30)).frame(width: max(0.6, s * 0.012), height: s * 0.36).offset(y: -s * 0.12).rotationEffect(.degrees(160))
            case .maps:
                Color(hex: 0xF4F1E8)
                Rectangle().fill(Color(hex: 0xB9E3A5)).frame(width: s * 0.45, height: s * 0.35).offset(x: -s * 0.3, y: -s * 0.3)
                Rectangle().fill(Color.white).frame(width: s * 1.4, height: s * 0.1).rotationEffect(.degrees(-30))
                Rectangle().fill(Color(hex: 0xFFD60A)).frame(width: s * 0.08, height: s * 1.4).rotationEffect(.degrees(20))
                Circle().fill(Color(hex: 0x007AFF)).frame(width: s * 0.36, height: s * 0.36).offset(x: s * 0.12, y: s * 0.12)
                glyph("location.fill", 0.2).offset(x: s * 0.12, y: s * 0.12)
            case .voiceMemos:
                grad(0x2C2C2E, 0x000000)
                glyph("waveform", 0.5, .white, weight: .light)
                Circle().fill(Color(hex: 0xFF3B30)).frame(width: s * 0.12, height: s * 0.12).offset(y: s * 0.32)
            case .settings:
                grad(0xDBDDDE, 0x898C90)
                glyph("gearshape.fill", 0.66, Color(hex: 0x48484A))
            default:
                IconArtwork(art: art, s: s)
            }
        }
        .frame(width: s, height: s)
    }

    private func calcKey(_ symbol: String, _ size: CGFloat, _ fill: Color) -> some View {
        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).fill(fill)
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.5, weight: .medium)).foregroundStyle(.white))
    }
}

/// One half of a compass needle (a thin diamond tip pointing up).
struct CompassNeedle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}
