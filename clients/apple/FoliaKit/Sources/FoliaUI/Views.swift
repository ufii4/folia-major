import FoliaKit
import SwiftUI
#if os(iOS)
import AVKit
#endif

// MARK: - Root

public struct RootView: View {
    @StateObject private var store: PlayerStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSettings = false

    public init(store: PlayerStore? = nil) {
        _store = StateObject(wrappedValue: store ?? PlayerStore())
    }

    private var theme: FoliaTheme { .system(colorScheme) }
    private var isDark: Bool { colorScheme == .dark }

    public var body: some View {
        content
            .tint(theme.accent)
            .sheet(isPresented: $showSettings) {
                SettingsView(store: store)
                    #if os(macOS)
                    .frame(width: 460, height: 420)
                    #endif
            }
            .onAppear {
                if case .failed = store.connection { showSettings = true }
            }
    }

    /// The stage: fluid themed background, Monet lyric rail, floating glass
    /// pill — Folia's player view composition (AppShell + VisualizerShell).
    private var stage: some View {
        ZStack {
            FluidBackground(theme: theme)
            VStack(spacing: 0) {
                ConnectionBanner(store: store, theme: theme) { showSettings = true }
                LyricsView(store: store, theme: theme)
            }
            VStack {
                Spacer()
                FloatingControls(store: store, theme: theme, isDark: isDark) {
                    showSettings = true
                }
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder private var content: some View {
        #if os(macOS)
        NavigationSplitView {
            SearchView(store: store, theme: theme)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            stage
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(theme.background)
        #else
        TabView {
            stage
                .tabItem { Label("Now Playing", systemImage: "music.note") }
            SearchView(store: store, theme: theme)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        #endif
    }
}

// MARK: - Connection banner

struct ConnectionBanner: View {
    @ObservedObject var store: PlayerStore
    let theme: FoliaTheme
    let openSettings: () -> Void

    var body: some View {
        switch store.connection {
        case .connected:
            EmptyView()
        case .connecting:
            banner("Connecting to \(store.config.serverURL.host ?? "server")…",
                   color: theme.secondary, icon: "antenna.radiowaves.left.and.right")
        case .failed(let reason):
            banner(reason, color: .orange, icon: "exclamationmark.triangle.fill")
        }
    }

    private func banner(_ text: String, color: Color, icon: String) -> some View {
        Button(action: openSettings) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(text).lineLimit(2).multilineTextAlignment(.leading)
                Spacer()
                Text("Fix").bold()
            }
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white.opacity(0.06))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search

struct SearchView: View {
    @ObservedObject var store: PlayerStore
    let theme: FoliaTheme
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search NetEase…", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { store.search(query) }
                .padding(10)
            List(Array(store.searchResults.enumerated()), id: \.element.id) { index, track in
                Button {
                    store.playNow(store.searchResults, index: index)
                } label: {
                    HStack {
                        ArtworkView(url: track.artUrl, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.name)
                                .foregroundStyle(theme.primary).lineLimit(1)
                            Text(track.artist).font(.caption)
                                .foregroundStyle(theme.secondary).lineLimit(1)
                        }
                        Spacer()
                        if store.currentTrack?.id == track.id {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(theme.background)
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
            Image(systemName: store.isOwner ? "hifispeaker.fill" : "hifispeaker")
        }
        #if os(macOS)
        .onAppear { outputs = AudioOutputs.list() }
        #endif
    }
}

#if os(iOS)
struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
#endif

// MARK: - Settings

public struct SettingsView: View {
    @ObservedObject var store: PlayerStore
    @Environment(\.dismiss) private var dismiss
    @State private var urlString: String
    @State private var token: String
    @State private var deviceName: String
    @State private var showScanner = false

    public init(store: PlayerStore) {
        self.store = store
        _urlString = State(initialValue: store.config.serverURL.absoluteString)
        _token = State(initialValue: store.config.token ?? "")
        _deviceName = State(initialValue: store.config.deviceName)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    statusRow
                }
                Section("folia-server") {
                    TextField("Server URL", text: $urlString)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Token", text: $token)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Device name", text: $deviceName)
                }
                Section {
                    Button { applyAndConnect() } label: {
                        Label("Connect", systemImage: "bolt.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    #if os(iOS)
                    if SetupScannerView.isSupported {
                        Button { showScanner = true } label: {
                            Label("Scan Setup Code", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    #endif
                } footer: {
                    Text("On the Mac running folia-server, open localhost:3766/pair and scan the code.")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showScanner) {
                scannerSheet
            }
            #else
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
    }

    @ViewBuilder private var statusRow: some View {
        HStack(spacing: 10) {
            switch store.connection {
            case .connecting:
                ProgressView().controlSize(.small)
                Text("Connecting…").foregroundStyle(.secondary)
            case .connected:
                Circle().fill(.green).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connected")
                    if let nick = store.serverNickname {
                        Text("NetEase: \(nick)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            case .failed(let reason):
                Circle().fill(.orange).frame(width: 9, height: 9)
                Text(reason).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func applyAndConnect() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
              url.scheme != nil else { return }
        var config = store.config
        config.serverURL = url
        config.token = token.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : token.trimmingCharacters(in: .whitespaces)
        config.deviceName = deviceName.isEmpty ? config.deviceName : deviceName
        store.reconfigure(config)
    }

    #if os(iOS)
    @ViewBuilder private var scannerSheet: some View {
        NavigationStack {
            SetupScannerView { payload in
                showScanner = false
                if let parsed = SetupCode.parse(payload) {
                    urlString = parsed.url.absoluteString
                    token = parsed.token
                    applyAndConnect()
                }
            }
            .ignoresSafeArea()
            .navigationTitle("Scan Setup Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showScanner = false }
                }
            }
        }
    }
    #endif
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
