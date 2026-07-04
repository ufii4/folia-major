import FoliaKit
import SwiftUI

/// The reason this app exists on the iPhone: synced lyrics for whatever is
/// playing anywhere. Highlight follows the mirror clock; tap a line to seek.
struct LyricsView: View {
    @ObservedObject var store: PlayerStore

    var body: some View {
        Group {
            if let doc = store.lyrics, !doc.lines.isEmpty {
                lyricsBody(doc)
            } else {
                VStack(spacing: 8) {
                    if let track = store.currentTrack {
                        Text(track.name).font(.title2.bold())
                        Text(track.artist).foregroundStyle(.secondary)
                        if store.unavailableTrackId == track.id {
                            Label("Not available in this region", systemImage: "nosign")
                                .font(.caption).foregroundStyle(.orange)
                        } else {
                            Text(store.lyrics == nil ? "" : "No lyrics")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40)).foregroundStyle(.quaternary)
                        Text("Play something").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func lyricsBody(_ doc: LyricDoc) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let active = doc.activeIndex(at: store.displayedPosition(now: ctx.date))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .center, spacing: 18) {
                        ForEach(Array(doc.lines.enumerated()), id: \.offset) { idx, line in
                            VStack(spacing: 4) {
                                Text(line.text)
                                    .font(.system(size: idx == active ? 24 : 18,
                                                  weight: idx == active ? .bold : .medium))
                                    .foregroundStyle(idx == active ? .primary : .secondary)
                                if let tl = line.translation {
                                    Text(tl)
                                        .font(.system(size: idx == active ? 16 : 13))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .multilineTextAlignment(.center)
                            .id(idx)
                            .onTapGesture { store.seek(to: line.time) }
                            .animation(.easeInOut(duration: 0.2), value: active)
                        }
                    }
                    .padding(.vertical, 120)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: active) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }
}
