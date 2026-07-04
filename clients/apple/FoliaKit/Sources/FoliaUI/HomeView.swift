import FoliaKit
import SwiftUI

/// Port of Folia's home (src/components/Home.tsx + Carousel3D.tsx):
/// wordmark top-left, content pills center (Playlists / Radio), search +
/// profile top-right, and a center-focused 3D cover carousel of the
/// account's playlists floating over the visualizer stage. Tapping the
/// focused cover opens the playlist; playing navigates to the player view.
struct HomeView: View {
    @ObservedObject var store: PlayerStore
    let theme: FoliaTheme
    let isDark: Bool
    let openSettings: () -> Void
    let enterPlayer: () -> Void

    enum HomeTab: String, CaseIterable {
        case playlists = "Playlists"
        case radio = "Radio"
    }

    @State private var tab: HomeTab = .playlists
    @State private var openedPlaylist: FoliaAPI.Playlist?
    @State private var showSearch = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            switch tab {
            case .playlists: carousel
            case .radio: radioCard
            }
            Spacer()
            Spacer().frame(height: 96) // room for the floating pill
        }
        .sheet(item: $openedPlaylist) { playlist in
            PlaylistSheet(store: store, theme: theme, playlist: playlist) {
                openedPlaylist = nil
                enterPlayer()
            }
            #if os(macOS)
            .frame(width: 520, height: 600)
            #endif
        }
        .sheet(isPresented: $showSearch) {
            SearchOverlay(store: store, theme: theme) {
                showSearch = false
                enterPlayer()
            }
            #if os(macOS)
            .frame(width: 520, height: 600)
            #endif
        }
        .onAppear { if store.playlists.isEmpty { store.loadLibrary() } }
    }

    // MARK: - Top bar (wordmark · pills · search/profile)

    private var topBar: some View {
        HStack {
            Text("Folia")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.primary)

            Spacer()

            HStack(spacing: 4) {
                ForEach(HomeTab.allCases, id: \.self) { t in
                    Button { tab = t } label: {
                        Text(t.rawValue)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(tab == t ? theme.background : theme.secondary)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(
                                Capsule().fill(tab == t ? theme.primary : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(.white.opacity(isDark ? 0.07 : 0.35)))

            Spacer()

            HStack(spacing: 10) {
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.secondary)
                        .padding(9)
                        .background(Circle().fill(.white.opacity(isDark ? 0.07 : 0.35)))
                }
                Button(action: openSettings) {
                    if let nick = store.serverNickname {
                        Text(String(nick.prefix(2)))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.primary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.white.opacity(isDark ? 0.1 : 0.45)))
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(theme.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: - Playlist carousel (Carousel3D)

    private var coverSide: CGFloat {
        #if os(macOS)
        260
        #else
        228
        #endif
    }

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 24) {
                ForEach(store.playlists) { playlist in
                    carouselCard(playlist)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 60)
        }
        .scrollTargetBehavior(.viewAligned)
        .frame(height: coverSide + 90)
        .overlay {
            if store.playlists.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(store.connected ? "Loading playlists…" : "Not connected")
                        .font(.caption).foregroundStyle(theme.secondary)
                }
            }
        }
    }

    private func carouselCard(_ playlist: FoliaAPI.Playlist) -> some View {
        Button { openedPlaylist = playlist } label: {
            VStack(spacing: 12) {
                ArtworkView(url: playlist.coverUrl, size: coverSide)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
                VStack(spacing: 3) {
                    Text(playlist.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.primary)
                        .lineLimit(1)
                    Text("\(playlist.trackCount) Tracks")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(theme.secondary)
                }
                .frame(width: coverSide)
            }
        }
        .buttonStyle(.plain)
        // Carousel3D: focused cover full-size, neighbors recede and dim
        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.84)
                .opacity(phase.isIdentity ? 1 : 0.55)
                .rotation3DEffect(
                    .degrees(phase.value * -14),
                    axis: (x: 0, y: 1, z: 0), perspective: 0.6
                )
        }
    }

    // MARK: - Radio (personal FM)

    private var radioCard: some View {
        Button { store.playFM(); enterPlayer() } label: {
            VStack(spacing: 14) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 44))
                    .foregroundStyle(theme.primary)
                Text("Personal FM")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.primary)
                Text("Tuned to your account")
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
            }
            .frame(width: 260, height: 220)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.white.opacity(isDark ? 0.06 : 0.4))
                    .overlay(RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.white.opacity(isDark ? 0.08 : 0.2)))
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Playlist sheet

struct PlaylistSheet: View {
    @ObservedObject var store: PlayerStore
    let theme: FoliaTheme
    let playlist: FoliaAPI.Playlist
    let onPlay: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [Track] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        store.playNow(tracks, index: index)
                        onPlay()
                    } label: {
                        HStack {
                            ArtworkView(url: track.artUrl, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.name).lineLimit(1)
                                Text(track.artist).font(.caption)
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .overlay { if loading { ProgressView() } }
            .navigationTitle(playlist.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !tracks.isEmpty else { return }
                        store.playNow(tracks, index: 0)
                        onPlay()
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            tracks = await store.tracks(of: playlist)
            loading = false
        }
    }
}

// MARK: - Search overlay (folia: search is an overlay, never a tab)

struct SearchOverlay: View {
    @ObservedObject var store: PlayerStore
    let theme: FoliaTheme
    let onPlay: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Search database…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { store.search(query) }
                    .padding(12)
                List(Array(store.searchResults.enumerated()), id: \.element.id) { index, track in
                    Button {
                        store.playNow(store.searchResults, index: index)
                        onPlay()
                    } label: {
                        HStack {
                            ArtworkView(url: track.artUrl, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.name).lineLimit(1)
                                Text(track.artist).font(.caption)
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }
}
