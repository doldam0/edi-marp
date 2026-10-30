import AppKit

/// A highlighter that paints a text storage. Markdown, CSS, and plain text all
/// share this so the editor can host any file the workspace holds.
protocol SyntaxHighlighter: AnyObject {
    var baseAttributes: [NSAttributedString.Key: Any] { get }
    func update(font: NSFont)
    func highlight(_ storage: NSTextStorage)
}

/// No highlighting beyond the base font/color — for arbitrary text files.
final class PlainHighlighter: SyntaxHighlighter {
    private var font: NSFont
    init(font: NSFont) { self.font = font }
    var baseAttributes: [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: NSColor.textColor] }
    func update(font: NSFont) { self.font = font }
    func highlight(_ storage: NSTextStorage) {
        storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
    }
}

/// Lightweight regex highlighting for CSS / Marp theme files: comments,
/// at-rules, selectors, properties, values, strings, numbers, and colors.
final class CSSHighlighter: SyntaxHighlighter {
    private var font: NSFont
    private var boldFont: NSFont

    init(font: NSFont) {
        self.font = font
        boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    func update(font: NSFont) {
        self.font = font
        boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.textColor]
    }

    private static func re(_ p: String, _ opts: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: opts)
    }

    // Order matters: later rules paint over earlier ones.
    private static let property = re(#"([-A-Za-z]+)(\s*):"#, [.anchorsMatchLines])
    private static let atRule = re(#"@[-A-Za-z]+"#)
    private static let themeTag = re(#"/\*\s*@theme\b.*?\*/"#, [.dotMatchesLineSeparators])
    private static let string = re(#"("[^"\n]*"|'[^'\n]*')"#)
    private static let number = re(#"(?<![\w-])-?\d*\.?\d+(px|em|rem|%|vh|vw|pt|deg|s|ms|fr)?\b"#)
    private static let hexColor = re(#"#[0-9A-Fa-f]{3,8}\b"#)
    private static let important = re(#"!important\b"#)
    private static let comment = re(#"/\*[\s\S]*?\*/"#)

    func highlight(_ storage: NSTextStorage) {
        let text = storage.string
        let all = NSRange(location: 0, length: (text as NSString).length)
        storage.setAttributes(baseAttributes, range: all)

        func apply(_ regex: NSRegularExpression, group: Int = 0, _ attrs: [NSAttributedString.Key: Any]) {
            regex.enumerateMatches(in: text, options: [], range: all) { m, _, _ in
                guard let m, m.range(at: group).location != NSNotFound else { return }
                storage.addAttributes(attrs, range: m.range(at: group))
            }
        }

        let accent = NSColor.controlAccentColor
        let keyword = NSColor.systemPurple
        let literal = NSColor.systemIndigo
        let numberColor = NSColor.systemTeal
        let secondary = NSColor.secondaryLabelColor

        apply(Self.property, group: 1, [.foregroundColor: accent])
        apply(Self.atRule, [.foregroundColor: keyword, .font: boldFont])
        apply(Self.number, [.foregroundColor: numberColor])
        apply(Self.hexColor, [.foregroundColor: numberColor])
        apply(Self.string, [.foregroundColor: literal])
        apply(Self.important, [.foregroundColor: keyword])
        apply(Self.themeTag, [.foregroundColor: accent, .font: boldFont])
        apply(Self.comment, [.foregroundColor: secondary])
    }
}
