import Foundation

/// Lyric document with optional word-level timing (NetEase yrc), matching
/// what folia's lyricsParser worker produces: lines, each with words when
/// the source has karaoke timing, plus line-level fallback (lrc).
public struct LyricDoc: Equatable, Sendable {
    public struct Word: Equatable, Sendable {
        public let text: String
        /// seconds
        public let start: Double
        public let duration: Double

        public init(text: String, start: Double, duration: Double) {
            self.text = text
            self.start = start
            self.duration = duration
        }
    }

    public struct Line: Equatable, Identifiable, Sendable {
        public let time: Double
        public let duration: Double?
        public let text: String
        public var translation: String?
        /// word-level timing when the source is yrc; nil for plain lrc
        public var words: [Word]?
        public var id: Double { time }

        public var endTime: Double? { duration.map { time + $0 } }
    }

    public var lines: [Line]
    public var hasWordTiming: Bool { lines.contains { $0.words != nil } }

    // MARK: - LRC (line-level)

    public static func parse(lrc: String, translation: String? = nil) -> LyricDoc {
        var lines = parseTrack(lrc).map {
            Line(time: $0.0, duration: nil, text: $0.1, translation: nil, words: nil)
        }
        mergeTranslation(&lines, translation)
        return LyricDoc(lines: lines)
    }

    // MARK: - YRC (word-level karaoke)
    // Format per line: [lineStartMs,lineDurMs](wStartMs,wDurMs,0)word(...)word
    // Interleaved JSON header lines ({"t":0,"c":[...]}) carry credits — skipped.

    public static func parse(yrc: String, translation: String? = nil) -> LyricDoc {
        var lines: [Line] = []
        let linePattern = #/^\[(\d+),(\d+)\]/#
        let wordPattern = #/\((\d+),(\d+),\d+\)([^(]*)/#

        for raw in yrc.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(raw)
            guard let header = s.firstMatch(of: linePattern) else { continue }
            let lineStart = (Double(header.output.1) ?? 0) / 1000
            let lineDur = (Double(header.output.2) ?? 0) / 1000
            var words: [Word] = []
            for m in s.matches(of: wordPattern) {
                let text = String(m.output.3)
                guard !text.isEmpty else { continue }
                words.append(Word(
                    text: text,
                    start: (Double(m.output.1) ?? 0) / 1000,
                    duration: (Double(m.output.2) ?? 0) / 1000
                ))
            }
            guard !words.isEmpty else { continue }
            let text = words.map(\.text).joined()
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            lines.append(Line(
                time: lineStart, duration: lineDur, text: text,
                translation: nil, words: words
            ))
        }
        lines.sort { $0.time < $1.time }
        var result = lines
        mergeTranslation(&result, translation)
        return LyricDoc(lines: result)
    }

    /// Pick the richer source: yrc with word timing when present, else lrc.
    public static func best(yrc: String?, lrc: String?, translation: String?) -> LyricDoc? {
        if let yrc, !yrc.isEmpty {
            let doc = parse(yrc: yrc, translation: translation)
            if !doc.lines.isEmpty { return doc }
        }
        if let lrc, !lrc.isEmpty {
            let doc = parse(lrc: lrc, translation: translation)
            if !doc.lines.isEmpty { return doc }
        }
        return nil
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

    // MARK: - Internals

    private static func mergeTranslation(_ lines: inout [Line], _ translation: String?) {
        guard let translation else { return }
        for (time, text) in parseTrack(translation) {
            if let idx = lines.firstIndex(where: { abs($0.time - time) < 0.5 }) {
                lines[idx].translation = text
            }
        }
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
