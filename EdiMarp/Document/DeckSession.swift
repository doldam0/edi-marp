import SwiftUI
import Combine
import EdiCore

/// The deck being edited and previewed in a window: the parsed deck, the
/// render, the active slide, and the markdown editor. Backed by a file on disk
/// (autosaved). Every mutation goes through `apply`, which turns a pure
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

    let fileURL: URL
    let editor: EditorController

    /// Workspace theme CSS passed to the engine; re-renders when it changes.
    var extraThemes: [String] { didSet { if extraThemes != oldValue { scheduleRender() } } }
    /// Folder used to resolve relative image paths in the preview.
    var assetRoot: URL?

    @Published private(set) var deck: Deck
    @Published private(set) var render: RenderResult?
    @Published private(set) var renderError: String?
    @Published private(set) var isRendering = false
    @Published private(set) var activeSlide = 0
    @Published private(set) var cursorLine = 0
    @Published private(set) var isDirty = false

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
    private var saveTask: Task<Void, Never>?
    private var reloadObserver: NSObjectProtocol?

    init(fileURL: URL, text: String, extraThemes: [String]) {
        self.fileURL = fileURL
        self.extraThemes = extraThemes
        let defaults = UserDefaults.standard
        deck = Deck(parsing: text)
        editor = EditorController(text: text, language: .markdown)
        layout = Layout(rawValue: defaults.string(forKey: Pref.layout) ?? "") ?? .split
        previewMode = PreviewMode(rawValue: defaults.string(forKey: Pref.previewMode) ?? "") ?? .focus
        inspectorShown = defaults.bool(forKey: Pref.inspector)

        editor.deck = deck
        editor.onTextChange = { [weak self] text in self?.textChanged(text) }
        editor.onSelectionChange = { [weak self] offset in self?.caretChanged(to: offset) }

        reloadObserver = NotificationCenter.default.addObserver(
            forName: MarpEngine.didReloadNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRender(delay: .milliseconds(100)) }
        }

        scheduleRender(delay: .zero)
    }

    deinit {
        if let reloadObserver { NotificationCenter.default.removeObserver(reloadObserver) }
    }

    // MARK: Derived

    var slideCount: Int { deck.slideCount }
    var activeSlideModel: Slide? { deck.slides.indices.contains(activeSlide) ? deck.slides[activeSlide] : nil }
    var aspect: Double { render?.aspect ?? 16 / 9 }
    var title: String { fileURL.deletingPathExtension().lastPathComponent }

    func svg(for index: Int) -> String? {
        guard let render, render.slides.indices.contains(index) else { return nil }
        return render.slides[index]
    }

    func notes(for index: Int) -> [String] {
        guard let render, render.notes.indices.contains(index) else { return [] }
        return render.notes[index]
    }

    // MARK: Text flow

    private func textChanged(_ text: String) {
        deck = Deck(parsing: text)
        editor.deck = deck
        caretMoved(to: editor.caretOffset)
        scheduleRender()
        scheduleSave(text)
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
        if slide != activeSlide {
            activeSlide = slide
            editor.activeSlide = slide
        }
    }

    func scheduleRender(delay: Duration = .milliseconds(60)) {
        renderTask?.cancel()
        let source = deck.source
        let themes = extraThemes
        isRendering = true
        renderTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            do {
                let result = try await MarpEngine.shared.render(source, extraThemes: themes)
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

    // MARK: Saving

    private func scheduleSave(_ text: String) {
        isDirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.saveNow(text)
        }
    }

    func saveNow(_ text: String? = nil) {
        let text = text ?? editor.text
        do {
            try text.data(using: .utf8)?.write(to: fileURL, options: .atomic)
            isDirty = false
        } catch {
            Diag.log("save failed: \(error)")
        }
    }

    // MARK: Navigation

    func selectSlide(_ index: Int, focusEditor: Bool = false, caret: Caret = .start) {
        guard deck.slides.indices.contains(index) else { return }
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
