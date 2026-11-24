import SwiftUI

/// iOS 4 multitasking bar: recently used internal apps on linen; long-press to show close badges.
/// The first page holds music playback controls, as in iOS 4.
/// Only RetroPhone's own internal apps are listed — other iOS apps are never controlled.
struct MultitaskingTray: View {
    @Environment(AppRouter.self) private var router
    @State private var closing = false

    var body: some View {
        let apps = router.recents.filter { $0 != router.currentApp }
        let iconSize: CGFloat = 57
        ZStack(alignment: .top) {
            WallpaperView(choice: .builtin(.linen))
            LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).frame(height: 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    musicControls.containerRelativeFrame(.horizontal)
                    let pages = stride(from: 0, to: max(apps.count, 1), by: 4).map { Array(apps[$0..<min($0 + 4, apps.count)]) }
                    ForEach(Array(pages.enumerated()), id: \.offset) { _, pageApps in
                        HStack(spacing: 0) {
                            ForEach(pageApps) { app in
                                VStack(spacing: 4) {
                                    RetroIconView(art: app.art, size: iconSize)
                                        .overlay(alignment: .topLeading) {
                                            if closing {
                                                Button { withAnimation { router.close(app) } } label: {
                                                    Image(systemName: "minus.circle.fill")
                                                        .font(.system(size: 24))
                                                        .foregroundStyle(.white, Color(hex: 0xD8261A))
                                                        .shadow(radius: 2)
                                                }
                                                .offset(x: -10, y: -10)
                                                .accessibilityLabel(LF("%@ 종료", L(app.nameKo)))
                                            }
                                        }
                                    IconLabel(text: L(app.nameKo), size: 11, width: 76)
                                }
                                .wiggle(closing, seed: app.rawValue)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if closing { closing = false; return }
                                    router.open(app)
                                }
                                .onLongPressGesture(minimumDuration: 0.5) {
                                    Haptics.tap(.heavy)
                                    closing = true
                                }
                            }
                            ForEach(0..<(4 - pageApps.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                        }
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .defaultScrollAnchor(.trailing)
            .padding(.top, 14)
            .frame(height: SpringboardView.trayHeight)
        }
        .onChange(of: router.multitaskingVisible) { _, v in if !v { closing = false } }
        .accessibilityIdentifier("multitaskingTray")
    }

    private var musicControls: some View {
        let music = MusicService.shared
        return VStack(spacing: 4) {
            HStack(spacing: 40) {
                trayButton("backward.fill", L("이전")) { music.previous() }
                trayButton(music.isPlaying ? "pause.fill" : "play.fill", music.isPlaying ? L("일시 정지") : L("재생")) { music.togglePlayPause() }
                trayButton("forward.fill", L("다음")) { music.next() }
                RetroIconView(art: .music, size: 44).onTapGesture { router.open(.music) }
            }
            Text(music.nowPlaying?.title ?? (music.isAuthorized ? L("재생 중인 음악 없음") : L("음악 보관함 접근 필요")))
                .font(.retroFixed(12, .bold)).foregroundStyle(.white).shadow(color: .black, radius: 0, y: -1)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
    }

    private func trayButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(.white)
                .shadow(color: .black, radius: 0, y: -1)
                .frame(width: 40, height: 40)
        }
        .disabled(!MusicService.shared.isAuthorized)
        .opacity(MusicService.shared.isAuthorized ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}
