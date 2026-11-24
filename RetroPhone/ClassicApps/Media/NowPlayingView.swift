import MediaPlayer
import SwiftUI
import UIKit

/// iOS 4 iPod "Now Playing": black, big artwork with reflection, translucent title bar,
/// scrubber with repeat/shuffle, transport controls and the system volume slider.
struct NowPlayingView: View {
    var onBack: () -> Void

    @State private var showsScrubber = true
    @State private var repeatMode: MPMusicRepeatMode = MusicService.shared.player.repeatMode
    @State private var shuffleMode: MPMusicShuffleMode = MusicService.shared.player.shuffleMode
    @State private var scrubValue: Double?
    @Environment(\.deviceInsets) private var insets
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let music = MusicService.shared
        let item = music.nowPlaying
        GeometryReader { geo in
            let width = geo.size.width
            let statusHeight = max(20, insets.top)
            ZStack(alignment: .top) {
                Color.black
                VStack(spacing: 0) {
                    Color.clear.frame(height: statusHeight)
                    artwork(item: item, side: width)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.25)) { showsScrubber.toggle() }
                        }
                    reflection(item: item, side: width)
                    Spacer(minLength: 0)
                }
                VStack(spacing: 0) {
                    Color.clear.frame(height: statusHeight)
                    titleBar(item: item)
                    if showsScrubber {
                        scrubberPanel(item: item)
                            .transition(.opacity)
                    }
                    Spacer(minLength: 0)
                    controlsBar
                    Color.black.frame(height: insets.bottom)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            repeatMode = music.player.repeatMode
            shuffleMode = music.player.shuffleMode
            music.refresh()
        }
    }

    // MARK: Artwork

    private func artworkImage(item: MPMediaItem?, side: CGFloat) -> UIImage? {
        item?.artwork?.image(at: CGSize(width: side * displayScale, height: side * displayScale))
    }

    @ViewBuilder
    private func artworkContent(_ image: UIImage?, side: CGFloat) -> some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: side, height: side)
                .clipped()
        } else {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x4A4A4A), Color(hex: 0x1C1C1C)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.4, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0x9A9A9A), Color(hex: 0x5A5A5A)],
                                                    startPoint: .top, endPoint: .bottom))
            }
            .frame(width: side, height: side)
        }
    }

    private func artwork(item: MPMediaItem?, side: CGFloat) -> some View {
        artworkContent(artworkImage(item: item, side: side), side: side)
            .contentShape(Rectangle())
            .accessibilityLabel(L("앨범 아트워크"))
    }

    private func reflection(item: MPMediaItem?, side: CGFloat) -> some View {
        let height = side * 0.35
        return artworkContent(artworkImage(item: item, side: side), side: side)
            .scaleEffect(x: 1, y: -1)
            .frame(width: side, height: height, alignment: .top)
            .clipped()
            .mask(LinearGradient(colors: [Color.white.opacity(0.4), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Bars

    private func titleBar(item: MPMediaItem?) -> some View {
        ZStack {
            BarBackground(style: .blackTranslucent)
            VStack(spacing: 1) {
                Text(item?.artist ?? " ")
                    .foregroundStyle(Color(hex: 0xA8A8A8))
                Text(item?.title ?? L("재생 중인 항목 없음"))
                    .foregroundStyle(.white)
                Text(item?.albumTitle ?? " ")
                    .foregroundStyle(Color(hex: 0xA8A8A8))
            }
            .font(.retroFixed(12, .bold))
            .lineLimit(1)
            .shadow(color: .black, radius: 0, y: -1)
            .padding(.horizontal, 70)
            HStack {
                ClassicBarButton(title: L("뒤로"), kind: .back, systemImage: "arrow.left", barStyle: .blackTranslucent) {
                    onBack()
                }
                Spacer()
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 44)
    }

    private func scrubberPanel(item: MPMediaItem?) -> some View {
        let music = MusicService.shared
        return HStack(spacing: 8) {
            Button { cycleRepeat() } label: {
                Image(systemName: repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(repeatActive ? Color(hex: 0x5AB4FF) : .white)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("반복"))
            .accessibilityValue(repeatActive ? L("켬") : L("끔"))

            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let duration = item?.playbackDuration ?? 0
                let playerTime = music.player.currentPlaybackTime
                let current = scrubValue ?? (playerTime.isFinite ? max(0, playerTime) : 0)
                HStack(spacing: 6) {
                    Text(MediaFormat.duration(current))
                        .frame(width: 42, alignment: .trailing)
                    RetroScrubber(value: current, total: duration,
                                  onScrub: { scrubValue = $0 },
                                  onCommit: { time in
                                      music.player.currentPlaybackTime = time
                                      scrubValue = nil
                                  })
                    Text("-" + MediaFormat.duration(max(0, duration - current)))
                        .frame(width: 46, alignment: .leading)
                }
                .font(.retroFixed(12, .bold))
                .foregroundStyle(.white)
            }

            Button { toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(shuffleActive ? Color(hex: 0x5AB4FF) : .white)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("셔플"))
            .accessibilityValue(shuffleActive ? L("켬") : L("끔"))
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .background(Color.black.opacity(0.6))
    }

    private var controlsBar: some View {
        let music = MusicService.shared
        return VStack(spacing: 8) {
            HStack {
                Spacer()
                transportButton("backward.end.fill", label: L("이전")) { music.previous() }
                Spacer()
                transportButton(music.isPlaying ? "pause.fill" : "play.fill",
                                label: music.isPlaying ? L("일시 정지") : L("재생")) { music.togglePlayPause() }
                Spacer()
                transportButton("forward.end.fill", label: L("다음")) { music.next() }
                Spacer()
            }
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0xBBBBBB))
                SystemVolumeSlider()
                    .frame(height: 30)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0xBBBBBB))
            }
            .padding(.horizontal, 22)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            LinearGradient(stops: [
                .init(color: Color(hex: 0x4A4A4A, opacity: 0.92), location: 0),
                .init(color: Color(hex: 0x1E1E1E, opacity: 0.95), location: 0.45),
                .init(color: Color.black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1) }
    }

    private func transportButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.35), radius: 3)
                .frame(width: 64, height: 44)
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(label)
    }

    // MARK: Modes

    private var repeatActive: Bool { repeatMode == .all || repeatMode == .one }
    private var shuffleActive: Bool { shuffleMode == .songs || shuffleMode == .albums }

    private func cycleRepeat() {
        Haptics.selection()
        switch repeatMode {
        case .all: repeatMode = .one
        case .one: repeatMode = .none
        default: repeatMode = .all
        }
        MusicService.shared.player.repeatMode = repeatMode
    }

    private func toggleShuffle() {
        Haptics.selection()
        shuffleMode = shuffleActive ? .off : .songs
        MusicService.shared.player.shuffleMode = shuffleMode
    }
}

/// Blue-filled track with a silver knob; drag to seek.
struct RetroScrubber: View {
    var value: Double
    var total: Double
    var onScrub: (Double) -> Void
    var onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knob: CGFloat = 18
            let fraction = total > 0 ? min(1, max(0, value / total)) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0x1A1A1A), Color(hex: 0x5A5A5A)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 8)
                    .overlay(Capsule().stroke(Color.black.opacity(0.7), lineWidth: 1))
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xA8D0FF), Color(hex: 0x2E6FD8)], startPoint: .top, endPoint: .bottom))
                    .frame(width: max(8, width * fraction), height: 8)
                Circle()
                    .fill(LinearGradient(colors: [Color.white, Color(hex: 0xB4B4B4)], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                    .offset(x: (width - knob) * fraction)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in onScrub(time(at: g.location.x, width: width)) }
                    .onEnded { g in onCommit(time(at: g.location.x, width: width)) }
            )
        }
        .frame(height: 28)
        .disabled(total <= 0)
        .accessibilityElement()
        .accessibilityLabel(L("재생 위치"))
        .accessibilityValue(MediaFormat.duration(value))
    }

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0, total > 0 else { return 0 }
        return Double(min(1, max(0, x / width))) * total
    }
}

/// System route-aware volume slider (MPVolumeView). Hidden by the system in the Simulator.
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = UIColor(red: 0.35, green: 0.62, blue: 1, alpha: 1)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
