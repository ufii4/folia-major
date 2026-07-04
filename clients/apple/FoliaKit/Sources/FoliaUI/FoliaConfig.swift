import Foundation

/// Client-side settings. The device id is minted once and kept — it is this
/// device's identity in the hub (ownership survives reconnects by id).
public struct FoliaConfig: Sendable {
    public var serverURL: URL
    public var token: String?
    public var deviceId: String
    public var deviceName: String
    public var platform: String

    static var defaults: UserDefaults { .standard }

    public static func load() -> FoliaConfig {
        let d = defaults
        let env = ProcessInfo.processInfo.environment

        #if os(macOS)
        let fallbackURL = "http://127.0.0.1:3766"
        let platform = "macos"
        let fallbackName = Host.current().localizedName ?? "Mac"
        #else
        let fallbackURL = "http://ufira.local:3766"
        let platform = "ios"
        let fallbackName = "iPhone"
        #endif

        let urlString = env["FOLIA_SERVER_URL"]
            ?? d.string(forKey: "folia.serverURL")
            ?? fallbackURL

        var deviceId = d.string(forKey: "folia.deviceId") ?? ""
        if deviceId.isEmpty {
            deviceId = "\(platform)-\(UUID().uuidString.prefix(8).lowercased())"
            d.set(deviceId, forKey: "folia.deviceId")
        }

        return FoliaConfig(
            serverURL: URL(string: urlString) ?? URL(string: fallbackURL)!,
            token: env["FOLIA_TOKEN"] ?? d.string(forKey: "folia.token"),
            deviceId: deviceId,
            deviceName: d.string(forKey: "folia.deviceName") ?? fallbackName,
            platform: platform
        )
    }

    public func save() {
        let d = Self.defaults
        d.set(serverURL.absoluteString, forKey: "folia.serverURL")
        d.set(token, forKey: "folia.token")
        d.set(deviceName, forKey: "folia.deviceName")
    }
}
