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

    private let highlighter: SyntaxHighlighter
    private var highlighting = false
    private var boundsObserver: NSObjectProtocol?

    init(text: String, language: Language = .markdown) {
        self.language = language
        let defaults = UserDefaults.standard
        fontSize = CGFloat(defaults.double(forKey: Pref.editorFontSize)).clamped(10, 28)
        showGutter = defaults.bool(forKey: Pref.showGutter)
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
        textView.isContinuousSpellCheckingEnabled = true
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
