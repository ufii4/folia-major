import FoliaKit
import SwiftUI

/// Strict port of Folia's Monet lyrics rail
/// (src/components/visualizer/monet/MonetLyricsRail.tsx).
///
/// Distance-based tone falloff (lines 90-122):
///   active:        opacity 1.00, scale 1.00, blur 0,   weight semibold
///   waiting dist N: opacity clamp(0.72-(N-1)·0.18, 0.36…0.72)
///                   scale   clamp(0.92·0.9^(N-1), 0.68…0.92)
///                   blur    N==1 ? 0.7 : 1.8+(N-2)·0.8
///   passed dist N:  opacity clamp(0.52-(N-1)·0.12, 0.28…0.52)
///                   blur    1.1+(N-1)·0.7
/// Scroll spring (line 69-74): stiffness 142, damping 28, mass 0.82
/// → ζ≈1.3 (no overshoot), response ≈ 0.48s.
/// Active line sits at 46% of viewport height. Tap a line to seek
/// (sanctioned by RemoteLyricOverlay's click-to-seek).
struct LyricsView: View {
    @ObservedObject var store: PlayerStore
    let theme: FoliaTheme

    private static let railSpring = Animation.spring(response: 0.48, dampingFraction: 1.0)

    var body: some View {
        Group {
            if let doc = store.lyrics, !doc.lines.isEmpty {
                rail(doc)
            } else {
                emptyState
            }
        }
    }

    // MARK: - Rail

    private func rail(_ doc: LyricDoc) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let active = doc.activeIndex(at: store.displayedPosition(now: ctx.date)) ?? -1
            GeometryReader { geo in
                let anchorY = geo.size.height * 0.46
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(Array(doc.lines.enumerated()), id: \.offset) { idx, line in
                        lineView(line, tone: tone(idx: idx, active: active))
                            .onTapGesture { store.seek(to: line.time) }
                    }
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: anchorY - offsetOfLine(max(active, 0), in: doc))
                .animation(Self.railSpring, value: active)
            }
            .clipped()
            .mask(edgeFade)
        }
    }

    private struct Tone {
        let opacity: Double
        let scale: Double
        let blur: Double
        let weight: Font.Weight
        let isActive: Bool
    }

    private func tone(idx: Int, active: Int) -> Tone {
        if idx == active {
            return Tone(opacity: 1, scale: 1, blur: 0, weight: .semibold, isActive: true)
        }
        let n = Double(abs(idx - active))
        let scale = min(max(0.92 * pow(0.9, n - 1), 0.68), 0.92)
        if idx > active || active < 0 {
            // waiting
            let opacity = min(max(0.72 - (n - 1) * 0.18, 0.36), 0.72)
            let blur = n == 1 ? 0.7 : 1.8 + (n - 2) * 0.8
            return Tone(opacity: opacity, scale: scale, blur: blur, weight: .medium, isActive: false)
        } else {
            // passed
            let opacity = min(max(0.52 - (n - 1) * 0.12, 0.28), 0.52)
            let blur = 1.1 + (n - 1) * 0.7
            return Tone(opacity: opacity, scale: scale, blur: blur, weight: .medium, isActive: false)
        }
    }

    @ViewBuilder
    private func lineView(_ line: LyricDoc.Line, tone: Tone) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(line.text)
                .font(.system(size: 27, weight: tone.weight))
                .foregroundStyle(tone.isActive ? theme.primary : theme.secondary)
                // Active glow, Visualizer.tsx glow layer (single soft pass)
                .shadow(color: tone.isActive ? theme.accent.opacity(0.35) : .clear,
                        radius: 10)
            if let tl = line.translation {
                Text(tl)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.secondary.opacity(tone.isActive ? 1 : 0.8))
            }
        }
        .multilineTextAlignment(.leading)
        .opacity(tone.opacity)
        .scaleEffect(tone.scale, anchor: .leading)
        .blur(radius: tone.blur)
        .contentShape(Rectangle())
    }

    /// Estimated y-offset of a line in the VStack. Lines wrap rarely at 27pt
    /// on phone width; a fixed estimate keeps the rail math cheap and the
    /// spring hides residual error, matching Monet's damped scroll feel.
    private func offsetOfLine(_ index: Int, in doc: LyricDoc) -> CGFloat {
        var y: CGFloat = 0
        for i in 0..<max(index, 0) {
            y += 33 + 26 // line height + spacing
            if doc.lines[i].translation != nil { y += 24 }
        }
        return y
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.10),
                .init(color: .black, location: 0.82),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            if let track = store.currentTrack {
                Text(track.name)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(theme.primary)
                Text(track.artist)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.secondary)
                if store.unavailableTrackId == track.id {
                    Label("Not available in this region", systemImage: "nosign")
                        .font(.caption)
                        .foregroundStyle(theme.accent)
                        .padding(.top, 4)
                }
            } else {
                Image(systemName: "music.note.list")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.secondary.opacity(0.5))
                Text("Play something")
                    .foregroundStyle(theme.secondary.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
