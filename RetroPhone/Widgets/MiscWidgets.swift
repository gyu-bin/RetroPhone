import SwiftUI
import Photos
import MediaPlayer

// MARK: - Analog clock

struct AnalogClockWidget: View {
    var size: WidgetSize
    var frame: CGSize
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x3A3A3A), Color(hex: 0x0E0E0E)], startPoint: .top, endPoint: .bottom)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                AnalogClockFace(date: ctx.date, diameter: min(frame.width, frame.height) * 0.86)
            }
        }
    }
}

struct AnalogClockFace: View {
    var date: Date
    var diameter: CGFloat
    var body: some View {
        let cal = Calendar.current
        let h = Double(cal.component(.hour, from: date) % 12)
        let m = Double(cal.component(.minute, from: date))
        let s = Double(cal.component(.second, from: date))
        let d = diameter
        ZStack {
            Circle().fill(RadialGradient(colors: [.white, Color(hex: 0xE2E2E2)], center: UnitPoint(x: 0.45, y: 0.4), startRadius: 0, endRadius: d * 0.6))
            Circle().stroke(LinearGradient(colors: [Color(hex: 0xBDBDBD), Color(hex: 0x5A5A5A)], startPoint: .top, endPoint: .bottom), lineWidth: d * 0.03)
            ForEach(1...12, id: \.self) { i in
                Text("\(i)").font(.retroFixed(d * 0.11, .bold)).foregroundStyle(Color(hex: 0x1A1A1A))
                    .offset(y: -d * 0.36).rotationEffect(.degrees(Double(i) * 30))
                    .rotationEffect(.degrees(0))
            }
            .hidden(d < 80)
            ForEach(0..<60, id: \.self) { i in
                Rectangle().fill(Color(hex: 0x2A2A2A)).frame(width: i % 5 == 0 ? d * 0.018 : d * 0.007, height: i % 5 == 0 ? d * 0.06 : d * 0.03)
                    .offset(y: -d * 0.455).rotationEffect(.degrees(Double(i) * 6))
            }
            hand(width: d * 0.045, length: d * 0.26, angle: (h + m / 60) * 30, color: Color(hex: 0x111111))
            hand(width: d * 0.03, length: d * 0.38, angle: (m + s / 60) * 6, color: Color(hex: 0x111111))
            hand(width: d * 0.012, length: d * 0.42, angle: s * 6, color: Color(hex: 0xD8261A))
            Circle().fill(Color(hex: 0xD8261A)).frame(width: d * 0.05)
        }
        .frame(width: d, height: d)
        .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
        .accessibilityElement()
        .accessibilityLabel(RetroFormat.time(date))
    }

    private func hand(width: CGFloat, length: CGFloat, angle: Double, color: Color) -> some View {
        Capsule().fill(color).frame(width: width, height: length)
            .offset(y: -length / 2 + width)
            .rotationEffect(.degrees(angle))
            .shadow(color: .black.opacity(0.35), radius: 1, x: 1, y: 1)
    }
}

private extension View {
    @ViewBuilder func hidden(_ hide: Bool) -> some View { if hide { EmptyView() } else { self } }
}

// MARK: - Digital clock

struct DigitalClockWidget: View {
    var size: WidgetSize
    var frame: CGSize
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2A2A2A), Color(hex: 0x000000)], startPoint: .top, endPoint: .bottom)
            WidgetGloss(strength: 0.18)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(spacing: 2) {
                    Text(RetroFormat.time(ctx.date, seconds: size == .wide))
                        .font(.custom("HelveticaNeue-Light", fixedSize: size == .small ? 30 : 48))
                        .foregroundStyle(LinearGradient(colors: [.white, Color(hex: 0xB8C4D0)], startPoint: .top, endPoint: .bottom))
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .shadow(color: Color(hex: 0x7FB0FF).opacity(0.4), radius: 4)
                    EmbossedText(text: RetroFormat.lockDate(ctx.date), size: 12, weight: .regular, color: Color(hex: 0xBFC6CE))
                }
                .padding(8)
            }
        }
    }
}

// MARK: - Photo

struct PhotoWidget: View {
    var size: WidgetSize
    var frame: CGSize
    @State private var image: UIImage?
    @State private var index = 0

    var body: some View {
        let lib = PhotoLibraryService.shared
        ZStack {
            Color(hex: 0x111111)
            if let image {
                Image(uiImage: image).resizable().scaledToFill().frame(width: frame.width, height: frame.height).clipped()
                    .transition(.opacity)
            } else {
                VStack(spacing: 6) {
                    RetroIconView(art: .photos, size: 40)
                    EmbossedText(text: lib.isDenied ? L("사진 접근이 거부됨") : (lib.canRead ? L("사진 없음") : L("사진 앱에서 접근을 허용하세요")), size: 11)
                }
                .padding(6)
            }
            WidgetGloss(strength: 0.15)
        }
        .task(id: lib.status) { await load() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            index += 1
            Task { await load() }
        }
    }

    private func load() async {
        let lib = PhotoLibraryService.shared
        guard lib.canRead else { return }
        let assets = lib.recentAssets(limit: 30)
        guard assets.count > 0 else { image = nil; return }
        let asset = assets.object(at: index % assets.count)
        let scale = UIScreen.main.scale
        let img = await lib.image(for: asset, size: CGSize(width: frame.width * scale, height: frame.height * scale))
        withAnimation(.easeInOut(duration: 0.6)) { image = img }
    }
}

// MARK: - Notes

struct NotesWidget: View {
    var size: WidgetSize
    var frame: CGSize
    var body: some View {
        let notes = NotesStore.shared.notes
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x9A6634), Color(hex: 0x5E3712)], startPoint: .top, endPoint: .bottom)
                EmbossedText(text: L("메모"), size: 13)
            }
            .frame(height: 22)
            ZStack(alignment: .topLeading) {
                LinedPaper(lineSpacing: 21)
                VStack(alignment: .leading, spacing: 0) {
                    if notes.isEmpty {
                        Text(L("메모 없음")).foregroundStyle(Color(hex: 0x8A6A2A))
                    }
                    ForEach(notes.prefix(size == .small ? 3 : (size == .wide ? 3 : 9))) { note in
                        HStack {
                            Text(note.title).lineLimit(1)
                            Spacer()
                            if size != .small {
                                Text(RetroFormat.date(note.modified, template: "MMMd")).foregroundStyle(Color(hex: 0x8A6A2A))
                            }
                        }
                        .frame(height: 21)
                    }
                }
                .font(.custom("MarkerFelt-Thin", fixedSize: 15))
                .foregroundStyle(Color(hex: 0x3A2A10))
                .padding(.horizontal, 10)
                .padding(.top, 3)
            }
        }
    }
}

/// Yellow legal-pad paper.
struct LinedPaper: View {
    var lineSpacing: CGFloat
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(hex: 0xFFF6B8), Color(hex: 0xF8E27E)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            var y = lineSpacing
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color(hex: 0xD6B860).opacity(0.7)))
                y += lineSpacing
            }
            ctx.fill(Path(CGRect(x: 6, y: 0, width: 1, height: size.height)), with: .color(Color(hex: 0xE07A6A).opacity(0.5)))
        }
    }
}

// MARK: - Music

struct MusicWidget: View {
    var size: WidgetSize
    var frame: CGSize
    var body: some View {
        let music = MusicService.shared
        let item = music.nowPlaying
        ZStack {
            LinearGradient(colors: [Color(hex: 0x6A6E74), Color(hex: 0x2A2C30)], startPoint: .top, endPoint: .bottom)
            WidgetGloss(strength: 0.25)
            if size == .small {
                VStack(spacing: 6) {
                    artwork(item, size: frame.height * 0.42)
                    EmbossedText(text: item?.title ?? placeholderText(music), size: 11)
                    controls(music, iconSize: 16)
                }
                .padding(8)
            } else {
                HStack(spacing: 12) {
                    artwork(item, size: frame.height * 0.72)
                    VStack(alignment: .leading, spacing: 4) {
                        EmbossedText(text: item?.title ?? placeholderText(music), size: 15)
                        EmbossedText(text: item?.artist ?? "", size: 12, weight: .regular, color: Color(hex: 0xD0D4DA))
                        Spacer(minLength: 2)
                        controls(music, iconSize: 20)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        }
    }

    private func placeholderText(_ m: MusicService) -> String {
        m.isAuthorized ? L("재생 중인 음악 없음") : L("음악 앱에서 접근을 허용하세요")
    }

    @ViewBuilder
    private func artwork(_ item: MPMediaItem?, size: CGFloat) -> some View {
        if let img = item?.artwork?.image(at: CGSize(width: size * 2, height: size * 2)) {
            Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
        } else {
            RetroIconView(art: .music, size: size, gloss: true)
        }
    }

    private func controls(_ m: MusicService, iconSize: CGFloat) -> some View {
        HStack(spacing: iconSize) {
            Button { Haptics.tap(); m.previous() } label: { Image(systemName: "backward.fill") }.accessibilityLabel(L("이전"))
            Button { Haptics.tap(); m.togglePlayPause() } label: { Image(systemName: m.isPlaying ? "pause.fill" : "play.fill") }
                .accessibilityLabel(m.isPlaying ? L("일시 정지") : L("재생"))
            Button { Haptics.tap(); m.next() } label: { Image(systemName: "forward.fill") }.accessibilityLabel(L("다음"))
        }
        .font(.system(size: iconSize))
        .foregroundStyle(.white)
        .shadow(color: .black, radius: 0, y: -1)
        .buttonStyle(.plain)
        .disabled(!m.isAuthorized)
        .opacity(m.isAuthorized ? 1 : 0.4)
    }
}
