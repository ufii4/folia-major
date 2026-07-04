import Foundation

/// Parses the pairing payload from the server's /pair QR:
/// folia://setup?url=http%3A%2F%2Fufira.local%3A3766&token=abc123
public enum SetupCode {
    public static func parse(_ string: String) -> (url: URL, token: String)? {
        guard let comps = URLComponents(string: string),
              comps.scheme == "folia", comps.host == "setup",
              let items = comps.queryItems,
              let urlString = items.first(where: { $0.name == "url" })?.value,
              let url = URL(string: urlString),
              let token = items.first(where: { $0.name == "token" })?.value,
              !token.isEmpty
        else { return nil }
        return (url, token)
    }
}
