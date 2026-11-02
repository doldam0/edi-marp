import AppKit
import EdiCore

/// Owns the NSTextView for one document. The text view is the only thing
/// that writes to the text, so typing and GUI transforms share one undo stack.
@MainActor
final class EditorController: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    let scrollView: NSScrollView
    let textView: NSTextView
    let gutter: GutterView

    enum Language { case markdown, css, plain }

    var onTextChange: ((String) -> Void)?
    var onSelectionChange: ((Int) -> Void)?
    /// A private undo stack per editor, so each open file undoes on its own.
    let ownUndoManager = UndoManager()
    let language: Language

    var deck: Deck? {
        didSet { gutter.deck = deck }
    }

    var activeSlide: Int = 0 {
        didSet { gutter.activeSlide = activeSlide }
    }

    var fontSize: CGFloat {
        didSet { applyFont() }
    }

    var showGutter: Bool {
        didSet { scrollView.rulersVisible = showGutter }
    }

    var spellCheck: Bool {
        didSet { textView.isContinuousSpellCheckingEnabled = spellCheck }
    }

    private let highlighter: SyntaxHighlighter
    private var highlighting = false
    private var boundsObserver: NSObjectProtocol?

    init(text: String, language: Language = .markdown) {
        self.language = language
        let defaults = UserDefaults.standard
        fontSize = CGFloat(defaults.double(forKey: Pref.editorFontSize)).clamped(10, 28)
        showGutter = defaults.bool(forKey: Pref.showGutter)
        spellCheck = defaults.bool(forKey: Pref.spellCheck)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        switch language {
        case .markdown: highlighter = MarkdownHighlighter(font: font)
        case .css: highlighter = CSSHighlighter(font: font)
        case .plain: highlighter = PlainHighlighter(font: font)
        }

        scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as! NSTextView
        gutter = GutterView(textView: textView, scrollView: scrollView)
        super.init()
        gutter.marpMode = (language == .markdown)

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = gutter
        scrollView.rulersVisible = showGutter
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        textView.delegate = self
        textView.textStorage?.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = spellCheck
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = font
        textView.textColor = .textColor
        textView.insertionPointColor = .controlAccentColor
        textView.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]

        textView.string = text
        applyFont()

        // Let the surrounding SwiftUI view handle image drops (copy into the
        // workspace + insert markdown) instead of the text view inserting a
        // file path or attachment.
        textView.unregisterDraggedTypes()

        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.gutter.needsDisplay = true }
        }
    }

    deinit {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
    }

    // MARK: State

    var text: String { textView.string }
    var caretOffset: Int { textView.selectedRange().location }

    private func applyFont() {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        highlighter.update(font: font)
        textView.font = font
        textView.typingAttributes = highlighter.baseAttributes
        rehighlight()
    }

    private func rehighlight() {
        guard let storage = textView.textStorage else { return }
        highlighting = true
        storage.beginEditing()
        highlighter.highlight(storage)
        storage.endEditing()
        highlighting = false
        gutter.needsDisplay = true
    }

    // MARK: Mutations

    /// Replaces the whole text without touching the undo stack (external reloads).
    func replaceAll(with text: String) {
        let caret = textView.selectedRange()
        textView.string = text
        rehighlight()
        let location = min(caret.location, (text as NSString).length)
        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    /// Applies edits as one undoable, named action via `insertText`, the same
    /// high-level path as typing: it registers undo, fires the change
    /// delegates, and reverts cleanly. Coalescing is broken on both sides so
    /// each GUI transform is a discrete, independently reversible undo step.
    /// Edits are applied back-to-front so earlier offsets stay valid.
    func apply(_ edits: [Edit], actionName: String) {
        guard !edits.isEmpty else { return }
        let sorted = edits.sorted { $0.range.location > $1.range.location }
        let ranges = sorted.map { NSValue(range: $0.range) }
        let strings = sorted.map(\.insert)
        textView.breakUndoCoalescing()
        guard textView.shouldChangeText(inRanges: ranges, replacementStrings: strings),
              let storage = textView.textStorage else { return }
        storage.beginEditing()
        for edit in sorted {
            storage.replaceCharacters(in: edit.range, with: edit.insert)
        }
        storage.endEditing()
        textView.didChangeText()
        textView.breakUndoCoalescing()
        textView.undoManager?.setActionName(actionName)
    }

    func insertAtCaret(_ text: String, actionName: String) {
        apply([Edit(range: textView.selectedRange(), insert: text)], actionName: actionName)
        textView.window?.makeFirstResponder(textView)
    }

    /// VSCode-style comment toggle for Marp's `<!-- -->` comments. With a
    /// selection, wraps it (or unwraps if already wrapped); with none, toggles
    /// the current line. An empty target becomes an empty comment with the
    /// caret placed inside, ready to type.
    func toggleComment() {
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        let hasSelection = selection.length > 0
        let range: NSRange
        if hasSelection {
            range = selection
        } else {
            var line = ns.lineRange(for: NSRange(location: selection.location, length: 0))
            if line.length > 0, ns.character(at: line.location + line.length - 1) == 10 { line.length -= 1 }
            range = line
        }

        let text = ns.substring(with: range)
        let core = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstContent = text.firstIndex { !$0.isWhitespace }
        let leading = String(text[text.startIndex..<(firstContent ?? text.endIndex)])
        let afterLast = (text.lastIndex { !$0.isWhitespace }).map { text.index(after: $0) } ?? text.endIndex
        let trailing = firstContent == nil ? "" : String(text[afterLast...])

        let replacement: String
        let actionName: String
        var caretInsideEmpty = false
        if core.hasPrefix("<!--"), core.hasSuffix("-->"), core.count >= 7 {
            var inner = String(core.dropFirst(4).dropLast(3))
            if inner.hasPrefix(" ") { inner.removeFirst() }
            if inner.hasSuffix(" ") { inner.removeLast() }
            replacement = leading + inner + trailing
            actionName = "주석 해제"
        } else {
            replacement = leading + "<!-- " + core + " -->" + trailing
            actionName = "주석 추가"
            caretInsideEmpty = core.isEmpty && !hasSelection
        }

        apply([Edit(range: range, insert: replacement)], actionName: actionName)

        let length = (replacement as NSString).length
        if hasSelection {
            textView.setSelectedRange(NSRange(location: range.location, length: length))
        } else if caretInsideEmpty {
            let offset = range.location + (leading as NSString).length + ("<!-- " as NSString).length
            textView.setSelectedRange(NSRange(location: offset, length: 0))
        } else {
            textView.setSelectedRange(NSRange(location: range.location + length, length: 0))
        }
        textView.scrollRangeToVisible(textView.selectedRange())
        textView.window?.makeFirstResponder(textView)
    }

    /// A line's leading structural marker: indentation then a list bullet
    /// (`-`/`*`/`+`), an ordered marker (`1.`/`1)`), or a heading (`#`..`######`).
    /// Bold/italic should wrap the line's text, not its marker.
    private static let listPrefix = try! NSRegularExpression(pattern: #"^[ \t]*(?:#{1,6}|[-*+]|\d+[.)])[ \t]+"#)
    private static let indentPrefix = try! NSRegularExpression(pattern: #"^[ \t]*"#)

    /// Wraps the selection, or the current line's text, in `marker` for
    /// bold/italic, toggling it off when already wrapped. On a line with no
    /// selection it skips the leading list marker (`- `, `1. `, …) and
    /// indentation and leaves trailing whitespace alone; an empty line gets the
    /// markers with the caret between them.
    func toggleInlineWrap(_ marker: String, actionName: String) {
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        let hadSelection = selection.length > 0
        let range: NSRange
        if hadSelection {
            range = selection
        } else {
            var line = ns.lineRange(for: NSRange(location: selection.location, length: 0))
            if line.length > 0, ns.character(at: line.location + line.length - 1) == 10 { line.length -= 1 }
            let lineText = ns.substring(with: line)
            let full = NSRange(location: 0, length: (lineText as NSString).length)
            let prefix = Self.listPrefix.firstMatch(in: lineText, range: full)
                ?? Self.indentPrefix.firstMatch(in: lineText, range: full)
            let prefixLength = prefix?.range.length ?? 0
            var contentEnd = line.length
            while contentEnd > prefixLength, isWhitespace(ns.character(at: line.location + contentEnd - 1)) { contentEnd -= 1 }
            range = NSRange(location: line.location + prefixLength, length: max(0, contentEnd - prefixLength))
        }

        let text = ns.substring(with: range)
        let m = marker
        let wrapped = text.hasPrefix(m) && text.hasSuffix(m) && text.count >= 2 * m.count
        let replacement = wrapped ? String(text.dropFirst(m.count).dropLast(m.count)) : m + text + m
        apply([Edit(range: range, insert: replacement)], actionName: actionName)

        let mLen = (m as NSString).length
        let repLen = (replacement as NSString).length
        if !wrapped, text.isEmpty {
            textView.setSelectedRange(NSRange(location: range.location + mLen, length: 0))
        } else {
            textView.setSelectedRange(NSRange(location: range.location, length: repLen))
        }
        textView.window?.makeFirstResponder(textView)
    }

    private func isWhitespace(_ c: unichar) -> Bool { c == 32 || c == 9 }

    func moveCaret(to offset: Int, focus: Bool) {
        let length = (textView.string as NSString).length
        let range = NSRange(location: max(0, min(offset, length)), length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        if focus { textView.window?.makeFirstResponder(textView) }
    }

    /// The undo manager that actually receives this editor's edits.
    var effectiveUndoManager: UndoManager? { ownUndoManager }

    func focus() {
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: NSTextViewDelegate

    func textViewDidChangeSelection(_ notification: Notification) {
        onSelectionChange?(caretOffset)
    }

    func undoManager(for view: NSTextView) -> UndoManager? { ownUndoManager }

    // MARK: NSTextStorageDelegate

    /// The single source of truth for "the text changed". Unlike the
    /// `textDidChange` delegate, this fires for typing, programmatic edits, and
    /// undo/redo alike, so the parsed deck and the document never drift out of
    /// sync with what the text view actually holds.
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !highlighting else { return }
        highlighting = true
        highlighter.highlight(textStorage)
        highlighting = false
        gutter.needsDisplay = true
        onTextChange?(textStorage.string)
    }
}

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.max(lo, Swift.min(hi, self)) }
}
