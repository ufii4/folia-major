import Foundation
import FoliaKit
import MediaPlayer

/// Lock screen / Control Center presence. Feeds MPNowPlayingInfoCenter and
/// routes remote commands (lock screen, AirPods, media keys) back through
/// the hub — so a pause from the lock screen pauses *everywhere*.
@MainActor
final class NowPlayingBridge {
    private weak var store: PlayerStore?
    private var artworkTrackId: Int?
    private var artwork: MPMediaItemArtwork?
    private var lastInfoTrackId: Int?

    func wire(_ store: PlayerStore) {
        self.store = store
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak store] _ in
            store?.play(); return .success
        }
        center.pauseCommand.addTarget { [weak store] _ in
            store?.pause(); return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak store] _ in
            store?.playPause(); return .success
        }
        center.nextTrackCommand.addTarget { [weak store] _ in
            store?.next(); return .success
        }
        center.previousTrackCommand.addTarget { [weak store] _ in
            store?.prev(); return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak store] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            store?.seek(to: e.positionTime)
            return .success
        }
    }

    func update() {
        guard let store else { return }
        let center = MPNowPlayingInfoCenter.default()
        guard let track = store.currentTrack else {
            center.nowPlayingInfo = nil
            lastInfoTrackId = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: store.displayedPosition(),
            MPNowPlayingInfoPropertyPlaybackRate: store.state.playing ? 1.0 : 0.0,
        ]
        if let album = track.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let dt = track.dt {
            info[MPMediaItemPropertyPlaybackDuration] = Double(dt) / 1000
        }
        if let artwork, artworkTrackId == track.id {
            info[MPMediaItemPropertyArtwork] = artwork
        } else if artworkTrackId != track.id {
            fetchArtwork(track)
        }
        center.nowPlayingInfo = info
        #if os(macOS)
        center.playbackState = store.state.playing ? .playing : .paused
        #endif
        lastInfoTrackId = track.id
    }

    private func fetchArtwork(_ track: Track) {
        artworkTrackId = track.id
        artwork = nil
        guard let urlString = track.artUrl, let url = URL(string: urlString) else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = PlatformImage(data: data) else { return }
            guard let self, self.artworkTrackId == track.id else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.update()
        }
    }
}

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif
