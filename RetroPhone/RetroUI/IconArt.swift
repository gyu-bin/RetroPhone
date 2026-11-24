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

    var id: String { rawValue }
}

/// Icon background + artwork, clipped to the classic rounded square, with the iOS-style gloss.
struct RetroIconView: View {
    var art: IconArt
    var size: CGFloat
    var customImage: UIImage? = nil
    var gloss: Bool = true

    static func cornerRadius(_ size: CGFloat) -> CGFloat { size * 0.175 }

    var body: some View {
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
