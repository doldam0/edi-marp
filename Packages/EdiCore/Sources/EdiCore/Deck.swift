import Foundation

/// One `<!-- key: value -->` declaration found in the markdown.
public struct Directive: Equatable, Sendable {
    /// Directive name without the spot underscore (`_class` → `class`).
    public let key: String
    public let value: String
    /// `true` for `_key` (applies to this slide only).
    public let isSpot: Bool
    /// Absolute line index of the comment.
    public let line: Int

    public var isGlobal: Bool { Deck.globalDirectiveKeys.contains(key) }
}

/// A slide as it appears in the source: a line range plus the directives that
/// were declared in it and the ones that are in effect after inheritance.
public struct Slide: Equatable, Sendable, Identifiable {
    public let index: Int
    public var id: Int { index }
    /// Lines belonging to the slide (empty when the slide has no lines).
    public let lineRange: Range<Int>
    /// UTF-16 range from the start of the first line to the end of the last
    /// line, excluding the newline before the next `---`.
    public let contentRange: NSRange
    /// `contentRange` with leading/trailing blank lines stripped.
    public let trimmedRange: NSRange
    public let declared: [Directive]
    /// Local directives in effect for this slide (`class`, `paginate`, ...).
    public let effective: [String: String]
    /// Best-effort title: first heading, else first text line.
    public let title: String

    public var isBlank: Bool { trimmedRange.length == 0 }

    public func declared(_ key: String, spot: Bool? = nil) -> Directive? {
        declared.last { $0.key == key && (spot == nil || $0.isSpot == spot!) }
    }

    /// Classes applied to this slide by the effective `class` directive.
    public var classes: [String] {
        (effective["class"] ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}

/// A parsed Marp document. Parsing is the only way the app ever interprets the
/// markdown; everything else reads from here and writes back `Edit`s.
public struct Deck: Equatable, Sendable {
    public static let globalDirectiveKeys: Set<String> = [
        "marp", "theme", "style", "headingDivider", "size", "title", "author",
        "description", "keywords", "url", "image", "math", "lang",
    ]
    public static let localDirectiveKeys: Set<String> = [
        "paginate", "header", "footer", "class", "backgroundColor", "backgroundImage",
        "backgroundPosition", "backgroundRepeat", "backgroundSize", "color",
    ]

    public let source: String
    public let lines: [String]
    /// UTF-16 offset of each line start, with a sentinel equal to the total length.
    public let lineOffsets: [Int]
    /// Line range of the YAML front matter including both `---` fences.
    public let frontmatter: Range<Int>?
    public let frontmatterValues: [String: String]
    /// Global directives in effect (front matter + global comment directives).
    public let globals: [String: String]
    public let slides: [Slide]

    public var theme: String { globals["theme"] ?? "default" }
    public var slideCount: Int { slides.count }

    // MARK: Parsing

    private static let hrRegex = try! NSRegularExpression(pattern: #"^ {0,3}([-*_])(?: *\1){2,} *$"#)
    private static let directiveRegex = try! NSRegularExpression(pattern: #"^\s*<!--\s*(_?)([A-Za-z][A-Za-z0-9]*)\s*:\s*(.*?)\s*-->\s*$"#)
    private static let headingRegex = try! NSRegularExpression(pattern: #"^ {0,3}#{1,6}\s+(.+?)\s*#*\s*$"#)
    private static let listRegex = try! NSRegularExpression(pattern: #"^ {0,3}(?:[-*+]|\d+[.)])\s"#)

    public init(parsing source: String) {
        self.source = source
        let lines = source.components(separatedBy: "\n")
        self.lines = lines

        var offsets: [Int] = []
        offsets.reserveCapacity(lines.count + 1)
        var cursor = 0
        for line in lines {
            offsets.append(cursor)
            cursor += line.utf16.count + 1
        }
        offsets.append(cursor - 1) // sentinel: total length (last line has no "\n")
        self.lineOffsets = offsets

        // Front matter
        var fm: Range<Int>? = nil
        var fmValues: [String: String] = [:]
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            if let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" || $0.trimmingCharacters(in: .whitespaces) == "..." }) {
                fm = 0..<(close + 1)
                for line in lines[1..<close] {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                    var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if value.count >= 2, let f = value.first, let l = value.last, f == l, f == "\"" || f == "'" {
                        value = String(value.dropFirst().dropLast())
                    }
                    if !key.isEmpty, !key.hasPrefix("#") { fmValues[key] = value }
                }
            }
        }
        self.frontmatter = fm
        self.frontmatterValues = fmValues

        // Slide boundaries
        let bodyStart = fm?.upperBound ?? 0
        var starts: [Int] = [bodyStart]
        var separators: [Int] = []
        var inFence = false
        var fenceMarker: Character? = nil
        var prevLine: String? = nil
        for i in bodyStart..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = Deck.fenceMarker(trimmed) {
                if !inFence { inFence = true; fenceMarker = marker }
                else if marker == fenceMarker { inFence = false; fenceMarker = nil }
                prevLine = line
                continue
            }
            if !inFence, Deck.isHorizontalRule(line), !Deck.isSetextUnderline(line, previous: prevLine) {
                separators.append(i)
                starts.append(i + 1)
            }
            prevLine = line
        }

        // Directives + inheritance
        var globals = fmValues.filter { Deck.globalDirectiveKeys.contains($0.key) }
        var inherited = fmValues.filter { Deck.localDirectiveKeys.contains($0.key) }
        var slides: [Slide] = []
        for (n, start) in starts.enumerated() {
            let end = n < separators.count ? separators[n] : lines.count
            let lineRange = start..<end
            var declared: [Directive] = []
            for i in lineRange {
                let line = lines[i]
                let ns = line as NSString
                guard let m = Deck.directiveRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
                let spot = m.range(at: 1).length == 1
                let key = ns.substring(with: m.range(at: 2))
                let value = ns.substring(with: m.range(at: 3))
                declared.append(Directive(key: key, value: value, isSpot: spot, line: i))
            }
            var effective = inherited
            for d in declared {
                if d.isGlobal { if !d.isSpot { globals[d.key] = d.value } }
                else if d.isSpot { effective[d.key] = d.value }
                else { inherited[d.key] = d.value; effective[d.key] = d.value }
            }
            let contentRange = NSRange(location: offsets[start], length: max(0, (end < lines.count ? offsets[end] - 1 : offsets[lines.count]) - offsets[start]))
            let trimmed = Deck.trimmedRange(lines: lines, offsets: offsets, lineRange: lineRange, fallback: contentRange.location)
            let title = Deck.title(of: lines[lineRange])
            slides.append(Slide(index: n, lineRange: lineRange, contentRange: contentRange, trimmedRange: trimmed, declared: declared, effective: effective, title: title))
        }
        self.globals = globals
        self.slides = slides
    }

    private static func fenceMarker(_ trimmed: String) -> Character? {
        if trimmed.hasPrefix("```") { return "`" }
        if trimmed.hasPrefix("~~~") { return "~" }
        return nil
    }

    static func isHorizontalRule(_ line: String) -> Bool {
        hrRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// `---` directly under a paragraph line is a setext heading, not a slide break.
    static func isSetextUnderline(_ line: String, previous: String?) -> Bool {
        guard line.trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == "-" }) else { return false }
        guard let prev = previous?.trimmingCharacters(in: .whitespaces), !prev.isEmpty else { return false }
        if prev.hasPrefix("#") || prev.hasPrefix(">") || prev.hasPrefix("|") || prev.hasPrefix("<") { return false }
        if prev.hasPrefix("```") || prev.hasPrefix("~~~") || prev.hasSuffix("-->") { return false }
        if listRegex.firstMatch(in: prev, range: NSRange(location: 0, length: (prev as NSString).length)) != nil { return false }
        if isHorizontalRule(prev) { return false }
        return true
    }

    private static func trimmedRange(lines: [String], offsets: [Int], lineRange: Range<Int>, fallback: Int) -> NSRange {
        let nonBlank = lineRange.filter { !lines[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let first = nonBlank.first, let last = nonBlank.last else {
            return NSRange(location: fallback, length: 0)
        }
        let start = offsets[first]
        let end = offsets[last] + lines[last].utf16.count
        return NSRange(location: start, length: end - start)
    }

    private static func title(of lines: ArraySlice<String>) -> String {
        for line in lines {
            let ns = line as NSString
            if let m = headingRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                return stripInline(ns.substring(with: m.range(at: 1)))
            }
        }
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("<!--") || t.hasPrefix("![") || t.hasPrefix("```") || t.hasPrefix("~~~") || t.hasPrefix("$$") || t.hasPrefix("|") { continue }
            return stripInline(t)
        }
        return ""
    }

    private static func stripInline(_ s: String) -> String {
        var out = s
        for pat in [#"!\[[^\]]*\]\([^)]*\)"#, #"\[([^\]]*)\]\([^)]*\)"#, #"[*_`~]+"#] {
            out = out.replacingOccurrences(of: pat, with: pat.hasPrefix(#"\["#) ? "$1" : "", options: .regularExpression)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Queries

    public func offset(ofLine line: Int) -> Int {
        lineOffsets[max(0, min(line, lines.count))]
    }

    /// Range of a line's text, excluding its newline.
    public func lineRange(_ line: Int) -> NSRange {
        let l = max(0, min(line, lines.count - 1))
        return NSRange(location: lineOffsets[l], length: lines[l].utf16.count)
    }

    /// Range of a line including its trailing newline (or the preceding one for the last line).
    public func fullLineRange(_ line: Int) -> NSRange {
        let l = max(0, min(line, lines.count - 1))
        if l < lines.count - 1 {
            return NSRange(location: lineOffsets[l], length: lineOffsets[l + 1] - lineOffsets[l])
        }
        let start = l > 0 ? lineOffsets[l] - 1 : lineOffsets[l]
        return NSRange(location: start, length: lineOffsets[lines.count] - start)
    }

    public func lineIndex(atOffset offset: Int) -> Int {
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineOffsets[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    public func slideIndex(atLine line: Int) -> Int {
        var idx = 0
        for s in slides where s.lineRange.lowerBound <= line { idx = s.index }
        return idx
    }

    public func slideIndex(atOffset offset: Int) -> Int {
        slideIndex(atLine: lineIndex(atOffset: offset))
    }

    public func isBlank(line: Int) -> Bool {
        line < 0 || line >= lines.count || lines[line].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func text(_ range: NSRange) -> String {
        (source as NSString).substring(with: range)
    }

    /// Words, counting each CJK character as one.
    public var wordCount: Int {
        var count = 0
        var inWord = false
        for scalar in source.unicodeScalars {
            let v = scalar.value
            let isCJK = (0x3040...0x30FF).contains(v) || (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v) || (0xAC00...0xD7AF).contains(v)
            if isCJK { count += 1; inWord = false; continue }
            if scalar.properties.isAlphabetic || CharacterSet.decimalDigits.contains(scalar) {
                if !inWord { count += 1; inWord = true }
            } else {
                inWord = false
            }
        }
        return count
    }
}
