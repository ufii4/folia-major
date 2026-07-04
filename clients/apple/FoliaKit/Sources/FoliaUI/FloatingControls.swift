import FoliaKit
import SwiftUI
#if os(iOS)
import AVKit
#endif

/// Strict port of Folia's FloatingPlayerControls (FloatingPlayerControls.tsx):
/// bottom-centered glass pill (backdrop-blur-3xl, black/40 + white/5 border
/// in dark), 48px filled circular play button in theme primary with
/// background-colored glyph, secondary controls at 40% opacity, 6px capsule
/// progress with 10px monospaced timestamps at 60% opacity.
struct FloatingControls: View {
    @ObservedObject var store: PlayerStore
    let theme: FoliaTheme
    let isDark: Bool
    let openSettings: () -> Void

    @State private var scrubbing = false
    @State private var scrubPos: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                playButton
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(store.currentTrack?.name ?? "Nothing playing")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.primary)
                            .lineLimit(1)
                        if let artist = store.currentTrack?.artist, !artist.isEmpty {
                            Text(artist)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.secondary)
                                .lineLimit(1)
                        }
                    }
                    progressBar
                }
                secondaryControls
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(pill)
        .frame(maxWidth: 512)
        .padding(.horizontal, 16)
    }

    // MARK: - Pieces

    private var playButton: some View {
        Button { store.playPause() } label: {
            ZStack {
                Circle().fill(theme.primary)
                Image(systemName: store.state.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.background)
                    .offset(x: store.state.playing ? 0 : 1.5)
            }
            .frame(width: 48, height: 48)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var progressBar: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let duration = max(Double(store.currentTrack?.dt ?? 0) / 1000, 0.1)
            let pos = scrubbing ? scrubPos
                : min(store.displayedPosition(now: ctx.date), duration)
            HStack(spacing: 10) {
                timeLabel(pos)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(isDark ? 0.10 : 0.25))
                        Capsule().fill(theme.primary)
                            .frame(width: max(6, geo.size.width * pos / duration))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                scrubbing = true
                                scrubPos = min(max(0, v.location.x / geo.size.width), 1) * duration
                            }
                            .onEnded { _ in
                                store.seek(to: scrubPos)
                                scrubbing = false
                            }
                    )
                }
                .frame(height: 6)
                timeLabel(duration)
            }
        }
        .frame(height: 14)
    }

    private func timeLabel(_ t: Double) -> some View {
        let s = Int(t.rounded())
        return Text(String(format: "%d:%02d", s / 60, s % 60))
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(theme.secondary.opacity(0.6))
    }

    private var secondaryControls: some View {
        HStack(spacing: 10) {
            Button { store.prev() } label: {
                Image(systemName: "backward.fill").font(.system(size: 14))
            }
            Button { store.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 14))
            }
            DevicesMenu(store: store)
                .font(.system(size: 14))
            #if os(iOS)
            RoutePickerView()
                .frame(width: 22, height: 22)
            #endif
            Button(action: openSettings) {
                Image(systemName: "gearshape").font(.system(size: 14))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.primary.opacity(0.4))
    }

    private var pill: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(
                isDark ? Color.black.opacity(0.40) : Color.white.opacity(0.60)))
            .overlay(Capsule().strokeBorder(
                Color.white.opacity(isDark ? 0.05 : 0.20), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 25, y: 12)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.8),
                       value: configuration.isPressed)
    }
}
