import FoliaKit
import SwiftUI

// MARK: - Root

public struct RootView: View {
    @StateObject private var store: PlayerStore

    public init(store: PlayerStore? = nil) {
        _store = StateObject(wrappedValue: store ?? PlayerStore())
    }

    public var body: some View {
        #if os(macOS)
        NavigationSplitView {
            SearchView(store: store)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            VStack(spacing: 0) {
                LyricsView(store: store)
                Divider()
                NowPlayingBar(store: store)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        #else
        TabView {
            VStack(spacing: 0) {
                LyricsView(store: store)
                NowPlayingBar(store: store)
            }
            .tabItem { Label("Now Playing", systemImage: "music.note") }
            SearchView(store: store)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        #endif
    }
}

// MARK: - Search

struct SearchView: View {
    @ObservedObject var store: PlayerStore
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search NetEase…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.search(query) }
                if !store.connected {
                    Image(systemName: "wifi.slash").foregroundStyle(.red)
                        .help("Not connected to folia-server")
                }
            }
            .padding(10)
            List(Array(store.searchResults.enumerated()), id: \.element.id) { index, track in
                Button {
                    store.playNow(store.searchResults, index: index)
                } label: {
                    HStack {
                        ArtworkView(url: track.artUrl, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.name).lineLimit(1)
                            Text(track.artist).font(.caption)
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if store.currentTrack?.id == track.id {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Now playing bar

struct NowPlayingBar: View {
    @ObservedObject var store: PlayerStore
    @State private var scrubbing = false
    @State private var scrubPos: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let duration = Double(store.currentTrack?.dt ?? 0) / 1000
                let pos = scrubbing ? scrubPos : min(store.displayedPosition(now: ctx.date), max(duration, 0.1))
                VStack(spacing: 2) {
                    Slider(
                        value: Binding(
                            get: { pos },
                            set: { scrubPos = $0 }
                        ),
                        in: 0...max(duration, 0.1)
                    ) { editing in
                        if editing { scrubPos = pos }
                        scrubbing = editing
                        if !editing { store.seek(to: scrubPos) }
                    }
                    HStack {
                        Text(timeString(pos))
                        Spacer()
                        Text(timeString(duration))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                ArtworkView(url: store.currentTrack?.artUrl, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.currentTrack?.name ?? "Nothing playing").lineLimit(1)
                    Text(store.currentTrack?.artist ?? "").font(.caption)
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()

                Button { store.prev() } label: { Image(systemName: "backward.fill") }
                Button { store.playPause() } label: {
                    Image(systemName: store.state.playing ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                Button { store.next() } label: { Image(systemName: "forward.fill") }

                DevicesMenu(store: store)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private func timeString(_ t: Double) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Devices

struct DevicesMenu: View {
    @ObservedObject var store: PlayerStore
    #if os(macOS)
    @State private var outputs: [AudioOutput] = []
    @State private var selectedOutput: String?
    #endif

    var body: some View {
        Menu {
            Section("Play on") {
                ForEach(store.devices) { device in
                    Button {
                        store.transfer(to: device.id)
                    } label: {
                        let mark = device.id == store.state.ownerId ? "🔊 " : ""
                        let you = device.id == store.you ? " (this device)" : ""
                        Text("\(mark)\(device.name)\(you)")
                    }
                }
            }
            #if os(macOS)
            Section("Output device") {
                ForEach(outputs) { output in
                    Button {
                        selectedOutput = output.uid
                        store.setOutputDevice(uid: output.uid)
                    } label: {
                        Text("\(output.uid == selectedOutput ? "✓ " : "")\(output.name)")
                    }
                }
            }
            #endif
        } label: {
            Image(systemName: store.isOwner
                ? "hifispeaker.fill" : "hifispeaker")
        }
        #if os(macOS)
        .onAppear { outputs = AudioOutputs.list() }
        #endif
    }
}

// MARK: - Settings

public struct SettingsView: View {
    @AppStorage("folia.serverURL") private var serverURL = ""
    @AppStorage("folia.token") private var token = ""
    @AppStorage("folia.deviceName") private var deviceName = ""

    public init() {}

    public var body: some View {
        Form {
            Section("folia-server") {
                TextField("Server URL (http://host:3766)", text: $serverURL)
                    .autocorrectionDisabled()
                SecureField("Token", text: $token)
                TextField("Device name", text: $deviceName)
            }
            Section {
                Text("Changes apply on next launch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .padding()
        #endif
    }
}

// MARK: - Artwork

struct ArtworkView: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
