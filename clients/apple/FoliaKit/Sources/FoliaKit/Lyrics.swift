import Foundation

/// Parsed LRC document. Handles multiple timestamps per line and merges an
/// optional translation track by timestamp proximity.
public struct LyricDoc: Equatable, Sendable {
    public struct Line: Equatable, Identifiable, Sendable {
        public let time: Double
        public let text: String
        public var translation: String?
        public var id: Double { time }
    }

    public var lines: [Line]

    public static func parse(lrc: String, translation: String? = nil) -> LyricDoc {
        var lines = parseTrack(lrc).map { Line(time: $0.0, text: $0.1, translation: nil) }
        if let translation {
            let tl = parseTrack(translation)
            for (time, text) in tl {
                if let idx = lines.firstIndex(where: { abs($0.time - time) < 0.3 }) {
                    lines[idx].translation = text
                }
            }
        }
        return LyricDoc(lines: lines)
    }

    /// Index of the line active at `position`, nil before the first line.
    public func activeIndex(at position: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        var lo = 0, hi = lines.count - 1, ans = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= position {
                ans = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return ans >= 0 ? ans : nil
    }

    // [mm:ss.xx] and [mm:ss:xx] variants, multiple tags per line.
    private static let tagPattern = #/\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/#

    private static func parseTrack(_ text: String) -> [(Double, String)] {
        var out: [(Double, String)] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            let tags = line.matches(of: tagPattern)
            guard !tags.isEmpty else { continue }
            let content = line[tags.last!.range.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }
            for tag in tags {
                let m = Double(tag.output.1) ?? 0
                let s = Double(tag.output.2) ?? 0
                let fracRaw = tag.output.3.map(String.init) ?? "0"
                let frac = (Double(fracRaw) ?? 0) / pow(10, Double(fracRaw.count))
                out.append((m * 60 + s + frac, content))
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }
}
