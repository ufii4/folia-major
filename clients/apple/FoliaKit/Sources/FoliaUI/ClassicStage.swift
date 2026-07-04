import FoliaKit
import SwiftUI

/// Port of Folia's DEFAULT visualizer — the "classic" word stage
/// (src/components/visualizer/classic/Visualizer.tsx, registry default).
///
/// Only the ACTIVE line is on stage. Its words run a 3-state machine:
///   waiting: opacity 0, scale 0.5, blur 10, scattered offset (seeded)
///   active:  opacity 1, springs to place (stiffness 200 damping 20),
///            scale ×1.4 while singing, glow 0 0 20/40 activeColor
///   passed:  opacity 0.82, base scale, no glow
/// Line swap: enter opacity0/scale0.9/blur10 → exit opacity0/scale1.1/blur20.
/// Ambient breathing float: ±14px over 7s ("normal" intensity).
/// Translation + upcoming line render as the bottom subtitle overlay
/// (VisualizerSubtitleOverlay: bottom 112px above chrome).
/// LRC-only tracks degrade to one word per line — the whole line flies in.
struct ClassicStage: View {
    @ObservedObject var store: PlayerStore
    let theme: FoliaTheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let time = store.displayedPosition(now: ctx.date)
            let doc = store.lyrics
            let activeIdx = doc?.activeIndex(at: time)

            ZStack {
                if let doc, let idx = activeIdx {
                    let line = doc.lines[idx]
                    stageLine(line, time: time, seed: idx)
                        .id(idx)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9)),
                            removal: .opacity.combined(with: .scale(scale: 1.1))
                        ))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(y: breathing(ctx.date) - 40)
                } else {
                    idleCard
                }

                subtitleOverlay(doc: doc, activeIdx: activeIdx)
            }
            .animation(.easeOut(duration: 0.3), value: activeIdx)
        }
    }

    // MARK: - Active line, word by word

    private func stageLine(_ line: LyricDoc.Line, time: Double, seed: Int) -> some View {
        let words = line.words ?? [
            LyricDoc.Word(text: line.text, start: line.time,
                          duration: line.duration ?? 4)
        ]
        return FlowLayout(spacing: 14, lineSpacing: 10) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                wordView(word, time: time, seed: seed &* 31 &+ i)
            }
        }
        .padding(.horizontal, 30)
    }

    private enum WordPhase { case waiting, active, passed }

    @ViewBuilder
    private func wordView(_ word: LyricDoc.Word, time: Double, seed: Int) -> some View {
        // wordLookahead: words begin entering slightly before their timestamp
        let phase: WordPhase = time < word.start - 0.15 ? .waiting
            : (time < word.start + max(word.duration, 0.12) ? .active : .passed)

        // Deterministic per-word scatter, Visualizer.tsx "normal" intensity:
        // baseSpread 20, scale 0.8–1.4 seeded.
        let rx = seededRandom(seed, 1) // 0..1
        let ry = seededRandom(seed, 2)
        let rs = seededRandom(seed, 3)
        let baseScale = 0.85 + rs * 0.3

        let fontSize = wordFontSize
        Text(word.text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(phase == .waiting ? theme.secondary : theme.primary)
            .shadow(color: phase == .active ? theme.accent.opacity(0.85) : .clear,
                    radius: 10)
            .shadow(color: phase == .active ? theme.accent.opacity(0.45) : .clear,
                    radius: 22)
            .opacity(phase == .waiting ? 0 : (phase == .active ? 1 : 0.82))
            .scaleEffect(phase == .waiting ? 0.5 : (phase == .active ? baseScale * 1.18 : baseScale))
            .blur(radius: phase == .waiting ? 10 : 0)
            .offset(x: phase == .waiting ? (rx - 0.5) * 40 : 0,
                    y: phase == .waiting ? (ry - 0.5) * 40 : 0)
            .animation(.spring(response: 0.44, dampingFraction: 0.7), value: phase)
    }

    private var wordFontSize: CGFloat {
        // clamp(2.25rem, 6vw, 4.5rem) — phones land at the floor, desktops mid
        #if os(macOS)
        48
        #else
        34
        #endif
    }

    // MARK: - Subtitle overlay (translation + upcoming line)

    @ViewBuilder
    private func subtitleOverlay(doc: LyricDoc?, activeIdx: Int?) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                if let doc, let idx = activeIdx {
                    if let tl = doc.lines[idx].translation {
                        Text(tl)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(theme.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if idx + 1 < doc.lines.count {
                        Text(doc.lines[idx + 1].text)
                            .font(.system(size: 14))
                            .foregroundStyle(theme.secondary.opacity(0.55))
                            .blur(radius: 0.6)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 128)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Idle / no lyrics

    private var idleCard: some View {
        VStack(spacing: 10) {
            if let track = store.currentTrack {
                Text(track.name)
                    .font(.system(size: wordFontSize * 0.8, weight: .bold))
                    .foregroundStyle(theme.primary)
                    .multilineTextAlignment(.center)
                Text(track.artist)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.secondary)
                if store.unavailableTrackId == track.id {
                    Label("Not available in this region", systemImage: "nosign")
                        .font(.caption).foregroundStyle(theme.accent).padding(.top, 4)
                }
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 44))
                    .foregroundStyle(theme.secondary.opacity(0.4))
            }
        }
        .padding(.horizontal, 30)
    }

    // MARK: - Helpers

    /// "normal" breathing: ±14px, 7s cycle.
    private func breathing(_ date: Date) -> CGFloat {
        CGFloat(sin(date.timeIntervalSinceReferenceDate * 2 * .pi / 7) * 14)
    }

    private func seededRandom(_ seed: Int, _ salt: Int) -> Double {
        var h = UInt64(bitPattern: Int64(seed &* 2654435761 &+ salt &* 40503))
        h ^= h >> 33; h = h &* 0xFF51AFD7ED558CCD; h ^= h >> 33
        return Double(h % 10_000) / 10_000
    }
}

/// Centered wrapping layout for stage words (flex-wrap, content-center).
struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } +
            CGFloat(max(rows.count - 1, 0)) * lineSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        var index = 0
        for row in rows {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for size in row.sizes {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size))
                x += size.width + spacing
                index += 1
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var sizes: [CGSize] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let needed = row.sizes.isEmpty ? size.width : row.width + spacing + size.width
            if needed > maxWidth, !row.sizes.isEmpty {
                rows.append(Row(sizes: [size], width: size.width, height: size.height))
            } else {
                row.sizes.append(size)
                row.width = needed
                row.height = max(row.height, size.height)
                rows[rows.count - 1] = row
            }
        }
        return rows
    }
}
