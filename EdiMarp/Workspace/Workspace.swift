import SwiftUI
import EdiCore

/// A window's workspace: a folder holding deck markdown, theme CSS, and images.
/// Owns the active deck's `DeckSession`, the file tree, the workspace themes,
/// and the per-file editors behind the editor pane's "current file".
@MainActor
final class Workspace: ObservableObject {
    struct ThemeFile: Identifiable, Hashable {
        let name: String
        let url: URL
        var id: URL { url }
    }

    enum SidebarMode: String { case slides, files }

    let ref: WorkspaceRef
    let root: URL
    private let scoped: Bool

    @Published private(set) var deck: DeckSession
    @Published private(set) var deckURL: URL
    @Published private(set) var currentFileURL: URL
    @Published private(set) var themeFiles: [ThemeFile]
    @Published private(set) var decks: [URL]
    /// Pressed the brush with a built-in theme: show the create-theme prompt.
    @Published var showThemePrompt = false
    @Published var sidebarMode: SidebarMode = .slides
    /// Bumped to make the file explorer re-read the directory.
    @Published private(set) var treeVersion = 0

    private var editors: [URL: EditorController] = [:]
    private var saveTasks: [URL: Task<Void, Never>] = [:]

    init?(ref: WorkspaceRef) {
        guard let root = ref.resolve() else { return nil }
        self.ref = ref
        self.root = root
        scoped = root.startAccessingSecurityScopedResource()

        let decks = Workspace.findDecks(in: root)
        let deckURL: URL
        if let first = decks.first {
            deckURL = first
        } else {
            deckURL = root.appendingPathComponent("deck.md")
            try? Templates.blank(theme: "default").data(using: .utf8)?.write(to: deckURL, options: .atomic)
        }
        let themes = Workspace.findThemes(in: root)
        self.decks = Workspace.findDecks(in: root)
        self.deckURL = deckURL
        self.currentFileURL = deckURL
        self.themeFiles = themes

        let text = (try? String(contentsOf: deckURL, encoding: .utf8)) ?? ""
        let themeCSS = themes.map { (try? String(contentsOf: $0.url, encoding: .utf8)) ?? "" }
        deck = DeckSession(fileURL: deckURL, text: text, extraThemes: themeCSS)
        deck.assetRoot = root
        editors[deckURL] = deck.editor
        RecentWorkspaces.add(ref)
    }

    deinit {
        if scoped { root.stopAccessingSecurityScopedResource() }
    }

    // MARK: Files & editors

    var rootNode: FileNode { FileNode(url: root, isDirectory: true) }

    /// The editor shown in the editor pane for the current file.
    var currentEditor: EditorController? {
        currentFileURL == deckURL ? deck.editor : editors[currentFileURL]
    }

    var currentIsMarkdown: Bool { currentFileURL == deckURL }

    func open(_ url: URL) {
        showThemePrompt = false
        let ext = url.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            setActiveDeck(url)
        } else if FileNode(url: url).isTextEditable {
            ensureEditor(for: url)
            currentFileURL = url
        } else {
            // Non-text (e.g. an image): reveal it rather than opening in the editor.
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func ensureEditor(for url: URL) {
        guard editors[url] == nil else { return }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let ext = url.pathExtension.lowercased()
        let lang: EditorController.Language = ext == "css" ? .css
            : (ext == "md" || ext == "markdown" ? .markdown : .plain)
        let editor = EditorController(text: text, language: lang)
        editor.onTextChange = { [weak self] text in self?.fileEdited(url, text, isCSS: ext == "css") }
        editors[url] = editor
    }

    private func setActiveDeck(_ url: URL) {
        if url == deckURL { currentFileURL = url; return }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let newDeck = DeckSession(fileURL: url, text: text, extraThemes: currentThemeCSS())
        newDeck.assetRoot = root
        editors[deckURL] = nil
        deck = newDeck
        deckURL = url
        currentFileURL = url
        editors[url] = newDeck.editor
    }

    private func fileEdited(_ url: URL, _ text: String, isCSS: Bool) {
        scheduleSave(url, text)
        if isCSS {
            // A live theme edit: feed the freshest CSS to the deck and re-render.
            deck.extraThemes = currentThemeCSS()
        }
    }

    private func scheduleSave(_ url: URL, _ text: String) {
        saveTasks[url]?.cancel()
        saveTasks[url] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            try? text.data(using: .utf8)?.write(to: url, options: .atomic)
            self?.saveTasks[url] = nil
        }
    }

    /// Writes every open file immediately (⌘S, app termination).
    func saveAll() {
        deck.saveNow()
        for (url, editor) in editors where url != deckURL {
            try? editor.text.data(using: .utf8)?.write(to: url, options: .atomic)
        }
    }

    // MARK: Editor-pane shortcuts (</> and brush)

    var isShowingDeck: Bool { !showThemePrompt && currentFileURL == deckURL }
    var isShowingTheme: Bool { !showThemePrompt && currentFileURL == activeThemeFile?.url }
    var activeThemeFile: ThemeFile? { themeFiles.first { $0.name == deck.deck.theme } }

    func showDeckFile() { open(deckURL) }

    func showThemeFile() {
        if let tf = activeThemeFile {
            open(tf.url)
        } else {
            showThemePrompt = true
        }
    }

    /// Creates `<theme>-custom.css` seeded from the deck's current built-in
    /// theme, points the deck at it, and opens it for editing.
    func createCustomTheme() {
        let builtin = deck.deck.theme
        let name = uniqueThemeName(baseName: builtin == "default" ? "custom" : "\(builtin)-custom")
        let url = root.appendingPathComponent("\(name).css")
        let css = """
        /* @theme \(name) */

        @import '\(builtin)';

        /* 여기에 \(name) 커스텀 스타일을 작성하세요. */
        section {

        }
        """
        try? css.data(using: .utf8)?.write(to: url, options: .atomic)
        refreshThemes()
        deck.setGlobalDirective("theme", name)
        open(url)
    }

    func refreshThemes() {
        themeFiles = Workspace.findThemes(in: root)
        deck.extraThemes = currentThemeCSS()
        bumpTree()
    }

    private func currentThemeCSS() -> [String] {
        themeFiles.map { tf in
            if let editor = editors[tf.url] { return editor.text }
            return (try? String(contentsOf: tf.url, encoding: .utf8)) ?? ""
        }
    }

    private func uniqueThemeName(baseName: String) -> String {
        let existing = Set(themeFiles.map(\.name))
        if !existing.contains(baseName), !FileManager.default.fileExists(atPath: root.appendingPathComponent("\(baseName).css").path) {
            return baseName
        }
        var i = 2
        while existing.contains("\(baseName)-\(i)") || FileManager.default.fileExists(atPath: root.appendingPathComponent("\(baseName)-\(i).css").path) {
            i += 1
        }
        return "\(baseName)-\(i)"
    }

    // MARK: Tree

    func bumpTree() {
        decks = Workspace.findDecks(in: root)
        treeVersion += 1
    }

    // MARK: Scanning

    private static func findDecks(in root: URL) -> [URL] {
        children(of: root).filter { ["md", "markdown"].contains($0.pathExtension.lowercased()) }
    }

    private static func findThemes(in root: URL) -> [ThemeFile] {
        children(of: root)
            .filter { $0.pathExtension.lowercased() == "css" }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8),
                      let name = themeName(in: text) else { return nil }
                return ThemeFile(name: name, url: url)
            }
    }

    private static func children(of root: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    nonisolated static func themeName(in css: String) -> String? {
        guard let r = css.range(of: #"/\*\s*@theme\s+([A-Za-z0-9_-]+)"#, options: .regularExpression) else { return nil }
        let frag = String(css[r])
        return frag.range(of: #"[A-Za-z0-9_-]+$"#, options: .regularExpression).map { String(frag[$0]) }
    }
}
