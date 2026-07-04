import AVFoundation
import Foundation

/// Thin AVPlayer wrapper. Streams straight from the NetEase CDN — audio
/// never passes through folia-server. On macOS the output device is
/// selectable per-player; on iOS the system route (AirPlay picker) rules.
@MainActor
public final class PlayerEngine {
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    public private(set) var loadedTrackId: Int?
    public var onEnd: (() -> Void)?

    #if os(macOS)
    public var outputDeviceUID: String? {
        didSet { player?.audioOutputDeviceUniqueID = outputDeviceUID }
    }
    #endif

    public init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        #endif
    }

    public func load(trackId: Int, url: URL, at position: Double, playing: Bool) {
        stop()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        #if os(macOS)
        p.audioOutputDeviceUniqueID = outputDeviceUID
        #endif
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onEnd?() }
        }
        player = p
        loadedTrackId = trackId
        if position > 0.5 {
            p.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        }
        if playing {
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif
            p.play()
        }
    }

    public func play() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        player?.play()
    }

    public func pause() { player?.pause() }

    public func seek(to position: Double) {
        player?.seek(to: CMTime(seconds: position, preferredTimescale: 600))
    }

    public var currentTime: Double {
        guard let t = player?.currentTime(), t.isNumeric else { return 0 }
        return max(0, t.seconds)
    }

    public var isPlaying: Bool { (player?.rate ?? 0) > 0 }

    public func stop() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        loadedTrackId = nil
    }
}
