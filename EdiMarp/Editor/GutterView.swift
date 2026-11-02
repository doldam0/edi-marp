import AppKit
import EdiCore

/// Line-number ruler that also marks where each slide begins: the `---`
/// line gets a numbered badge instead of a line number.
final class GutterView: NSRulerView {
    weak var textView: NSTextView?
    var deck: Deck? { didSet { needsDisplay = true } }
    var activeSlide: Int = 0 { didSet { needsDisplay = true } }
    /// When false (CSS / plain files) the ruler shows line numbers only, with
    /// no slide badges and no markdown parsing.
    var marpMode = true { didSet { needsDisplay = true } }

    private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
    private let badgeFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 46
        // macOS 14+ no longer clips views to their bounds by default; the
        // ruler's background and separator otherwise bleed above the scroll
        // view, through the editor header and the window toolbar.
        clipsToBounds = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var requiredThickness: CGFloat { 46 }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        rect.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        guard let textView, let layout = textView.textLayoutManager, let content = layout.textContentManager else { return }
        // Only markdown decks carry slide structure; other files parse their own
        // line map cheaply (no slides) so numbering still works.
        let deck = marpMode ? (deck ?? Deck(parsing: textView.string)) : Deck(parsing: "")
        var badges: [Int: Int] = [:]
        if marpMode {
            for slide in deck.slides {
                badges[slide.index == 0 ? slide.lineRange.lowerBound : slide.lineRange.lowerBound - 1] = slide.index + 1
            }
        }
        let lineOf: (Int) -> Int = marpMode ? { deck.lineIndex(atOffset: $0) } : { offset in
            let s = textView.string as NSString
            var line = 0, i = 0
            while i < offset, i < s.length { if s.character(at: i) == 10 { line += 1 }; i += 1 }
            return line
        }

        let inset = textView.textContainerInset
        let visible = textView.visibleRect
        let topPoint = CGPoint(x: 0, y: max(0, visible.minY - inset.height))
        let start = layout.textLayoutFragment(for: topPoint)?.rangeInElement.location ?? layout.documentRange.location

        let numberAttrs: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: NSColor.tertiaryLabelColor]
        let activeAttrs: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: NSColor.secondaryLabelColor]
        let width = ruleThickness

        layout.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout, .ensuresExtraLineFragment]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let yInText = frame.minY + inset.height
            if yInText > visible.maxY { return false }
            let y = self.convert(NSPoint(x: 0, y: yInText), from: textView).y
            let lineHeight = fragment.textLineFragments.first?.typographicBounds.height ?? frame.height
            let offset = content.offset(from: layout.documentRange.location, to: fragment.rangeInElement.location)
            let line = lineOf(offset)
            let isActive = self.marpMode && deck.slideIndex(atLine: line) == self.activeSlide

            if let badge = badges[line] {
                // A badge sits on the `---` line above its slide, which belongs
                // to the *previous* slide, so highlight by the badge's own slide
                // (badge - 1), not the line's slide.
                let badgeActive = self.marpMode && badge - 1 == self.activeSlide
                let label = NSAttributedString(string: "\(badge)", attributes: [.font: self.badgeFont, .foregroundColor: NSColor.white])
                let size = label.size()
                let pill = NSRect(x: width - 8 - max(18, size.width + 10), y: y + (lineHeight - 16) / 2, width: max(18, size.width + 10), height: 16)
                (badgeActive ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setFill()
                NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
                label.draw(at: NSPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2))
            } else {
                let label = NSAttributedString(string: "\(line + 1)", attributes: isActive ? activeAttrs : numberAttrs)
                let size = label.size()
                label.draw(at: NSPoint(x: width - 8 - size.width, y: y + (lineHeight - size.height) / 2))
            }
            return true
        }
    }
}
