import SwiftUI
import Combine
import EdiCore

/// Per-window state: the parsed deck, the render, the active slide and the
/// editor controller. Every mutation goes through `apply`, which turns a pure
/// transform into one undoable text edit.
@MainActor
final class DeckSession: ObservableObject {
    enum Layout: String, CaseIterable, Identifiable {
        case editor, split, preview
        var id: String { rawValue }
        var title: String {
            switch self { case .editor: "편집기"; case .split: "분할"; case .preview: "미리보기" }
        }
        var symbol: String {
            switch self {
            case .editor: "rectangle.lefthalf.inset.filled"
            case .split: "rectangle.split.2x1"
            case .preview: "rectangle.righthalf.inset.filled"
            }
        }
    }

    enum PreviewMode: String { case focus, grid }
    enum Caret { case start, end }

    let document: DeckDocument
    let editor: EditorController

    @Published private(set) var deck: Deck
    @Published private(set) var render: RenderResult?
    @Published private(set) var renderError: String?
    @Published private(set) var isRendering = false
    @Published private(set) var activeSlide = 0
    @Published private(set) var cursorLine = 0
    @Published var fileURL: URL?

    @Published var layout: Layout {
        didSet { UserDefaults.standard.set(layout.rawValue, forKey: Pref.layout) }
    }
    @Published var previewMode: PreviewMode {
        didSet { UserDefaults.standard.set(previewMode.rawValue, forKey: Pref.previewMode) }
    }
    @Published var inspectorShown: Bool {
        didSet { UserDefaults.standard.set(inspectorShown, forKey: Pref.inspector) }
    }

    private var renderTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(document: DeckDocument) {
        self.document = document
        let defaults = UserDefaults.standard
        deck = Deck(parsing: document.text)
        editor = EditorController(text: document.text)
        layout = Layout(rawValue: defaults.string(forKey: Pref.layout) ?? "") ?? .split
        previewMode = PreviewMode(rawValue: defaults.string(forKey: Pref.previewMode) ?? "") ?? .focus
        inspectorShown = defaults.bool(forKey: Pref.inspector)

        editor.deck = deck
        editor.onTextChange = { [weak self] text in self?.textChanged(text) }
        editor.onSelectionChange = { [weak self] offset in self?.caretChanged(to: offset) }

        // Only genuinely external changes (Revert To…, file reload) flow back
        // into the editor. Delivered synchronously so `writingToDocument` is
        // still set for document writes we make ourselves — otherwise the
        // editor and the document would ping-pong forever.
        document.$text
            .dropFirst()
            .sink { [weak self] text in
                guard let self, !self.writingToDocument, self.editor.text != text else { return }
                // Replacing the text fires the editor's change signal, which
                // reparses the deck and re-renders; no manual sync needed here.
                self.editor.replaceAll(with: text)
            }
            .store(in: &cancellables)

        scheduleRender(delay: .zero)
    }

    // MARK: Derived

    var slideCount: Int { deck.slideCount }
    var activeSlideModel: Slide? { deck.slides.indices.contains(activeSlide) ? deck.slides[activeSlide] : nil }
    var aspect: Double { render?.aspect ?? 16 / 9 }
    var title: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? deck.globals["title"] ?? deck.slides.first?.title ?? "제목 없음"
    }

    func svg(for index: Int) -> String? {
        guard let render, render.slides.indices.contains(index) else { return nil }
        return render.slides[index]
    }

    func notes(for index: Int) -> [String] {
        guard let render, render.notes.indices.contains(index) else { return [] }
        return render.notes[index]
    }

    // MARK: Text flow

    /// True while we are writing the editor's text back into the document, so
    /// the document subscription does not treat it as an external change.
    private var writingToDocument = false

    private func textChanged(_ text: String) {
        if document.text != text {
            writingToDocument = true
            document.text = text
            writingToDocument = false
        }
        deck = Deck(parsing: text)
        editor.deck = deck
        caretMoved(to: editor.caretOffset)
        scheduleRender()
    }

    private var caretCoalescePending = false
    private var latestCaretOffset = 0

    /// Coalesces a burst of selection notifications (TextKit 2 can emit many
    /// during one layout pass) into a single state update per run-loop tick.
    private func caretChanged(to offset: Int) {
        latestCaretOffset = offset
        guard !caretCoalescePending else { return }
        caretCoalescePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.caretCoalescePending = false
            self.caretMoved(to: self.latestCaretOffset)
        }
    }

    private func caretMoved(to offset: Int) {
        let line = deck.lineIndex(atOffset: offset)
        let slide = deck.slideIndex(atLine: line)
        if line != cursorLine { cursorLine = line }
        if slide != activeSlide { activeSlide = slide }
    }

    func scheduleRender(delay: Duration = .milliseconds(60)) {
        renderTask?.cancel()
        let source = deck.source
        isRendering = true
        renderTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            do {
                let result = try await MarpEngine.shared.render(source)
                guard !Task.isCancelled, let self else { return }
                self.render = result
                self.renderError = nil
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.renderError = error.localizedDescription
                Diag.log("render failed: \(error)")
            }
            self?.isRendering = false
        }
    }

    // MARK: Navigation

    func selectSlide(_ index: Int, focusEditor: Bool = false, caret: Caret = .start) {
        guard deck.slides.indices.contains(index) else { return }
        // Already here with the caret inside this slide and no focus demanded:
        // nothing to do. This is what stops the sidebar-selection / caret-tracking
        // ping-pong from ever forming a loop.
        if index == activeSlide, !focusEditor, deck.slideIndex(atOffset: editor.caretOffset) == index {
            return
        }
        let slide = deck.slides[index]
        let offset = caret == .start ? slide.trimmedRange.location : NSMaxRange(slide.trimmedRange)
        activeSlide = index
        editor.moveCaret(to: offset, focus: focusEditor)
    }

    func goToLine(_ line: Int) {
        editor.moveCaret(to: deck.offset(ofLine: line), focus: true)
    }

    func nextSlide() { selectSlide(activeSlide + 1) }
    func previousSlide() { selectSlide(activeSlide - 1) }

    // MARK: Mutations

    /// Runs a pure transform against the current deck and applies the edits
    /// as one undo step named `name`.
    @discardableResult
    func apply(_ name: String, _ transform: (Deck) -> [Edit]) -> Bool {
        let edits = transform(deck)
        guard !edits.isEmpty else { return false }
        editor.apply(edits, actionName: name)
        return true
    }

    func insertSlide() {
        let index = activeSlide + 1
        apply("새 슬라이드") { Transforms.insertSlide($0, at: index) }
        selectSlide(min(index, slideCount - 1), focusEditor: true, caret: .end)
    }

    func duplicateSlide() {
        let index = activeSlide
        apply("슬라이드 복제") { Transforms.duplicateSlide($0, index) }
        selectSlide(index + 1)
    }

    func deleteSlide(_ index: Int? = nil) {
        let index = index ?? activeSlide
        apply("슬라이드 삭제") { Transforms.deleteSlide($0, index) }
        selectSlide(min(index, slideCount - 1))
    }

    func moveSlide(by delta: Int) {
        moveSlide(from: activeSlide, to: activeSlide + delta)
    }

    func moveSlide(from: Int, to: Int) {
        guard deck.slides.indices.contains(to), from != to else { return }
        apply("슬라이드 이동") { Transforms.moveSlide($0, from: from, to: to) }
        selectSlide(to)
    }

    func toggleClass(_ name: String) {
        let index = activeSlide
        apply("\(name) 전환") { Transforms.toggleClass($0, slide: index, name: name) }
    }

    func setSlideDirective(_ key: String, _ value: String?) {
        let index = activeSlide
        apply(value == nil ? "\(key) 제거" : "\(key) 설정") { Transforms.setSlideDirective($0, slide: index, key: key, value: value) }
    }

    func setGlobalDirective(_ key: String, _ value: String?) {
        apply("\(key) 설정") { Transforms.setGlobalDirective($0, key: key, value: value) }
    }

    func insertSnippet(_ snippet: Snippet) {
        editor.insertAtCaret(snippet.text, actionName: "\(snippet.title) 삽입")
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
