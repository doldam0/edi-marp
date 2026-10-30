import AppKit
import EdiCore

/// Line-number ruler that also marks where each slide begins: the `---`
/// line gets a numbered badge instead of a line number.
final class GutterView: NSRulerView {
    weak var textView: NSTextView?
    var deck: Deck? { didSet { needsDisplay = true } }
    var activeSlide: Int = 0 { didSet { needsDisplay = true } }

    private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
    private let badgeFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 46
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var requiredThickness: CGFloat { 46 }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        guard let textView, let layout = textView.textLayoutManager, let content = layout.textContentManager else { return }
        let deck = deck ?? Deck(parsing: textView.string)
        var badges: [Int: Int] = [:]
        for slide in deck.slides {
            badges[slide.index == 0 ? slide.lineRange.lowerBound : slide.lineRange.lowerBound - 1] = slide.index + 1
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
            let line = deck.lineIndex(atOffset: offset)
            let isActive = deck.slideIndex(atLine: line) == self.activeSlide

            if let badge = badges[line] {
                let label = NSAttributedString(string: "\(badge)", attributes: [.font: self.badgeFont, .foregroundColor: NSColor.white])
                let size = label.size()
                let pill = NSRect(x: width - 8 - max(18, size.width + 10), y: y + (lineHeight - 16) / 2, width: max(18, size.width + 10), height: 16)
                (isActive ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setFill()
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
