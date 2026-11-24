import MediaPlayer
import Observation
import UIKit

/// Music via MediaPlayer's system player, so playback continues in the system Music app
/// when RetroPhone is backgrounded. Only items in the user's local library are listed.
/// DRM-protected Apple Music streaming catalog playback would require MusicKit + subscription;
/// library items (including downloaded Apple Music tracks) play through the system player.
@Observable
final class MusicService {
    static let shared = MusicService()

    let player = MPMusicPlayerController.systemMusicPlayer
    private(set) var authorization: MPMediaLibraryAuthorizationStatus = MPMediaLibrary.authorizationStatus()
    private(set) var nowPlaying: MPMediaItem?
    private(set) var isPlaying = false

    var isDenied: Bool { authorization == .denied || authorization == .restricted }
    var isAuthorized: Bool { authorization == .authorized }

    private init() {
        guard isAuthorized else { return }
        startObserving()
    }

    private var observing = false
    private func startObserving() {
        guard !observing else { return }
        observing = true
        player.beginGeneratingPlaybackNotifications()
        let nc = NotificationCenter.default
        for name in [Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange,
                     .MPMusicPlayerControllerPlaybackStateDidChange] {
            nc.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        guard isAuthorized else { return }
        nowPlaying = player.nowPlayingItem
        isPlaying = player.playbackState == .playing
    }

    @discardableResult
    func requestAccess() async -> Bool {
        if isAuthorized { startObserving(); return true }
        let status = await withCheckedContinuation { cont in
            MPMediaLibrary.requestAuthorization { cont.resume(returning: $0) }
        }
        authorization = status
        if status == .authorized { startObserving() }
        return status == .authorized
    }

    func songs() -> [MPMediaItem] {
        guard isAuthorized else { return [] }
        return MPMediaQuery.songs().items ?? []
    }

    func albums() -> [MPMediaItemCollection] {
        guard isAuthorized else { return [] }
        return MPMediaQuery.albums().collections ?? []
    }

    func artists() -> [MPMediaItemCollection] {
        guard isAuthorized else { return [] }
        return MPMediaQuery.artists().collections ?? []
    }

    func playlists() -> [MPMediaItemCollection] {
        guard isAuthorized else { return [] }
        return MPMediaQuery.playlists().collections ?? []
    }

    func play(_ items: [MPMediaItem], startAt item: MPMediaItem? = nil) {
        guard !items.isEmpty else { return }
        player.setQueue(with: MPMediaItemCollection(items: items))
        if let item { player.nowPlayingItem = item }
        player.play()
        refresh()
    }

    func togglePlayPause() {
        if player.playbackState == .playing { player.pause() } else { player.play() }
        refresh()
    }

    func next() { player.skipToNextItem(); refresh() }
    func previous() {
        if player.currentPlaybackTime > 3 { player.skipToBeginning() } else { player.skipToPreviousItem() }
        refresh()
    }
}
