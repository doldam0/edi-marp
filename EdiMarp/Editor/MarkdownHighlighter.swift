import AppKit

/// Lightweight regex highlighting for Marp markdown. Runs over the whole
/// storage (decks are small) inside `didProcessEditing`, attributes only.
final class MarkdownHighlighter: SyntaxHighlighter {
    private struct Rule {
        let regex: NSRegularExpression
        let group: Int
        let attributes: () -> [NSAttributedString.Key: Any]
    }

    private static func re(_ p: String, _ opts: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: opts)
    }

    private let rules: [Rule]
    var font: NSFont
    var boldFont: NSFont
    var italicFont: NSFont

    init(font: NSFont) {
        self.font = font
        boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        rules = []
    }

    func update(font: NSFont) {
        self.font = font
        boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.textColor]
    }

    private static let frontmatter = re(#"\A---\n[\s\S]*?\n(?:---|\.\.\.)(?=\n|\z)"#, [])
    private static let fence = re(#"^ {0,3}(```|~~~)[^\n]*\n[\s\S]*?\n {0,3}\1[ \t]*$"#)
    private static let heading = re(#"^ {0,3}#{1,6} .*$"#)
    private static let rule = re(#"^ {0,3}([-*_])(?: *\1){2,} *$"#)
    private static let comment = re(#"<!--[\s\S]*?-->"#, [])
    private static let directive = re(#"<!--\s*(_?[A-Za-z][A-Za-z0-9]*)\s*:"#, [])
    private static let inlineCode = re(#"`[^`\n]+`"#)
    private static let bold = re(#"\*\*[^*\n]+\*\*|__[^_\n]+__"#)
    private static let italic = re(#"(?<![*\w])\*[^*\n]+\*(?!\*)|(?<![_\w])_[^_\n]+_(?!\w)"#)
    private static let link = re(#"!?\[[^\]\n]*\]\([^)\n]*\)"#)
    private static let listMarker = re(#"^ {0,3}(?:[-*+]|\d+[.)]) "#)
    private static let quote = re(#"^ {0,3}> ?.*$"#)
    private static let math = re(#"^\$\$[\s\S]*?^\$\$"#)

    func highlight(_ storage: NSTextStorage, in range: NSRange) {
        storage.setAttributes(baseAttributes, range: range)

        func apply(_ regex: NSRegularExpression, group: Int = 0, _ attrs: [NSAttributedString.Key: Any]) {
            regex.enumerateMatches(in: storage.string, options: [], range: range) { m, _, _ in
                guard let m, m.range(at: group).location != NSNotFound else { return }
                storage.addAttributes(attrs, range: m.range(at: group))
            }
        }

        let secondary = NSColor.secondaryLabelColor
        let tertiary = NSColor.tertiaryLabelColor
        let accent = NSColor.controlAccentColor
        let literal = NSColor.systemIndigo

        apply(Self.quote, [.foregroundColor: secondary, .font: italicFont])
        apply(Self.listMarker, [.foregroundColor: accent])
        apply(Self.heading, [.font: boldFont])
        apply(Self.bold, [.font: boldFont])
        apply(Self.italic, [.font: italicFont])
        apply(Self.link, [.foregroundColor: NSColor.linkColor])
        apply(Self.inlineCode, [.foregroundColor: literal])
        apply(Self.math, [.foregroundColor: literal])
        apply(Self.fence, [.foregroundColor: literal, .font: font])
        apply(Self.comment, [.foregroundColor: tertiary, .font: font])
        apply(Self.directive, group: 1, [.foregroundColor: accent])
        apply(Self.rule, [.foregroundColor: accent, .font: boldFont])
        apply(Self.frontmatter, [.foregroundColor: secondary, .font: font])
    }
}
