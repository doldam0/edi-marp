import Foundation

/// Pure transforms: `(Deck, …) -> [Edit]`. They never touch the editor; the
/// app applies the result through the text view so each one is a single undo
/// step and the markdown remains the only source of truth.
public enum Transforms {
    static let separator = "\n\n---\n\n"

    // MARK: Global directives (front matter)

    public static func setGlobalDirective(_ deck: Deck, key: String, value: String?) -> [Edit] {
        if let fm = deck.frontmatter {
            let inner = (fm.lowerBound + 1)..<(fm.upperBound - 1)
            if let line = inner.first(where: { directiveKey(deck.lines[$0]) == key }) {
                if let value {
                    return [Edit(range: deck.lineRange(line), insert: "\(key): \(value)")]
                }
                return [.delete(deck.fullLineRange(line))]
            }
            guard let value else { return [] }
            return [Edit(at: deck.offset(ofLine: fm.upperBound - 1), insert: "\(key): \(value)\n")]
        }
        guard let value else { return [] }
        var block = "---\nmarp: true\n"
        if key != "marp" { block += "\(key): \(value)\n" }
        block += "---\n\n"
        return [Edit(at: 0, insert: block)]
    }

    private static func directiveKey(_ line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : key
    }

    // MARK: Slide directives

    /// Sets (or removes, when `value` is nil) a directive on one slide. With
    /// `spot` the directive is written as `_key` so it applies to that slide only.
    public static func setSlideDirective(_ deck: Deck, slide index: Int, key: String, value: String?, spot: Bool = true) -> [Edit] {
        guard deck.slides.indices.contains(index) else { return [] }
        let slide = deck.slides[index]
        let existing = slide.declared(key, spot: spot) ?? slide.declared(key)
        if let existing {
            if let value {
                let prefix = existing.isSpot ? "_" : ""
                return [Edit(range: deck.lineRange(existing.line), insert: "<!-- \(prefix)\(key): \(value) -->")]
            }
            return [.delete(lineRangeCollapsingBlank(deck, line: existing.line, slide: slide))]
        }
        guard let value else { return [] }
        let prefix = spot ? "_" : ""
        return [Edit(at: slide.trimmedRange.location, insert: "<!-- \(prefix)\(key): \(value) -->\n\n")]
    }

    /// Deletes a line and, when that would leave two blank lines in a row (or a
    /// leading blank line in the slide), the blank line after it as well.
    private static func lineRangeCollapsingBlank(_ deck: Deck, line: Int, slide: Slide) -> NSRange {
        var range = deck.fullLineRange(line)
        let next = line + 1
        let prevBlankOrEdge = line == slide.lineRange.lowerBound || deck.isBlank(line: line - 1)
        if next < deck.lines.count, next < slide.lineRange.upperBound, deck.isBlank(line: next), prevBlankOrEdge {
            range = NSUnionRange(range, deck.fullLineRange(next))
        }
        return range
    }

    /// Toggles a class in the slide's spot `_class` directive.
    public static func toggleClass(_ deck: Deck, slide index: Int, name: String) -> [Edit] {
        guard deck.slides.indices.contains(index) else { return [] }
        let slide = deck.slides[index]
        var classes = (slide.declared("class", spot: true)?.value ?? "")
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if let i = classes.firstIndex(of: name) { classes.remove(at: i) } else { classes.append(name) }
        return setSlideDirective(deck, slide: index, key: "class", value: classes.isEmpty ? nil : classes.joined(separator: " "))
    }

    // MARK: Slide structure

    /// Inserts a slide so that it becomes slide `index`.
    public static func insertSlide(_ deck: Deck, at index: Int, body: String = "# ") -> [Edit] {
        let body = trimmed(body)
        let slides = deck.slides
        guard let first = slides.first, let last = slides.last else { return [Edit(at: 0, insert: body + "\n")] }
        if slides.count == 1, first.isBlank {
            return [Edit(range: first.contentRange, insert: body + "\n")]
        }
        if index <= 0 {
            return [Edit(at: first.trimmedRange.location, insert: body + separator)]
        }
        let anchor = index >= slides.count ? last : slides[index - 1]
        return [Edit(at: NSMaxRange(anchor.trimmedRange), insert: separator + body)]
    }

    public static func deleteSlide(_ deck: Deck, _ index: Int) -> [Edit] {
        let slides = deck.slides
        guard slides.indices.contains(index) else { return [] }
        if slides.count == 1 { return [.delete(slides[0].contentRange)] }
        if index == slides.count - 1 {
            let from = NSMaxRange(slides[index - 1].trimmedRange)
            return [.delete(NSRange(location: from, length: NSMaxRange(slides[index].trimmedRange) - from))]
        }
        let from = slides[index].trimmedRange.location
        return [.delete(NSRange(location: from, length: slides[index + 1].trimmedRange.location - from))]
    }

    public static func duplicateSlide(_ deck: Deck, _ index: Int) -> [Edit] {
        guard deck.slides.indices.contains(index) else { return [] }
        let slide = deck.slides[index]
        return [Edit(at: NSMaxRange(slide.trimmedRange), insert: separator + deck.text(slide.trimmedRange))]
    }

    public static func moveSlide(_ deck: Deck, from: Int, to: Int) -> [Edit] {
        let slides = deck.slides
        guard from != to, slides.indices.contains(from), slides.indices.contains(to) else { return [] }
        let lo = min(from, to), hi = max(from, to)
        var bodies = slides[lo...hi].map { deck.text($0.trimmedRange) }
        let moved = bodies.remove(at: from - lo)
        bodies.insert(moved, at: to - lo)
        let start = slides[lo].trimmedRange.location
        let end = NSMaxRange(slides[hi].trimmedRange)
        return [Edit(range: NSRange(location: start, length: end - start), insert: bodies.joined(separator: separator))]
    }

    private static func trimmed(_ s: String) -> String {
        var t = Substring(s)
        while let l = t.last, l.isNewline { t.removeLast() }
        while let f = t.first, f.isNewline { t.removeFirst() }
        return String(t)
    }
}
