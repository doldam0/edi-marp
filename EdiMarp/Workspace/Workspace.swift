import SwiftUI
import UniformTypeIdentifiers
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

    // MARK: Assets

    /// Images copied in by drag/paste/picker land here, beside the deck.
    static let assetsFolder = "assets"

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// Copies an external image into the workspace (or references one already
    /// inside it), then inserts an image tag at the deck's caret. The markdown
    /// stays the single source of truth; the preview serves the file by path.
    @discardableResult
    func insertImage(from sourceURL: URL) -> Bool {
        guard FileNode(url: sourceURL, isDirectory: false).isImage else { return false }
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let target: URL
        let rootPath = root.standardizedFileURL.path
        if sourceURL.standardizedFileURL.path.hasPrefix(rootPath + "/") {
            target = sourceURL // already in the workspace: reference it in place
        } else {
            guard let dir = assetsDirectory() else { return false }
            let dest = uniqueFile(in: dir, base: sourceURL.deletingPathExtension().lastPathComponent,
                                  ext: sourceURL.pathExtension)
            guard (try? FileManager.default.copyItem(at: sourceURL, to: dest)) != nil else { return false }
            target = dest
        }
        insertImageTag(for: target)
        return true
    }

    /// Writes raw image data (a paste, or a drag from another app) into the
    /// assets folder and inserts an image tag at the deck's caret.
    @discardableResult
    func insertImage(data: Data, fileExtension ext: String) -> Bool {
        guard !data.isEmpty, let dir = assetsDirectory() else { return false }
        let stamp = Self.stampFormatter.string(from: Date())
        let dest = uniqueFile(in: dir, base: "image-\(stamp)", ext: ext.isEmpty ? "png" : ext)
        guard (try? data.write(to: dest)) != nil else { return false }
        insertImageTag(for: dest)
        return true
    }

    /// Opens a picker to choose one or more images to import.
    func importImagesViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        panel.prompt = "추가"
        panel.message = "덱에 추가할 이미지를 선택하세요"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { insertImage(from: url) }
    }

    private func assetsDirectory() -> URL? {
        let dir = root.appendingPathComponent(Self.assetsFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue ? dir : nil
    }

    private func uniqueFile(in dir: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        let safeBase = base.isEmpty ? "image" : base
        let suffix = ext.isEmpty ? "" : ".\(ext.lowercased())"
        var candidate = dir.appendingPathComponent(safeBase + suffix)
        var n = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(safeBase)-\(n)\(suffix)")
            n += 1
        }
        return candidate
    }

    /// Inserts `![](path)` at the deck's caret, showing the deck first so the
    /// edit is visible, and refreshes the tree for any newly copied file.
    private func insertImageTag(for assetURL: URL) {
        showDeckFile()
        let rel = Workspace.relativePath(from: deckURL.deletingLastPathComponent(), to: assetURL)
        deck.editor.insertAtCaret("![](\(rel))", actionName: "이미지 삽입")
        bumpTree()
    }

    /// A forward-slash path from `base` (a folder) to `target`, as markdown wants.
    static func relativePath(from base: URL, to target: URL) -> String {
        let baseComps = base.standardizedFileURL.pathComponents
        let targetComps = target.standardizedFileURL.pathComponents
        var i = 0
        while i < baseComps.count, i < targetComps.count, baseComps[i] == targetComps[i] { i += 1 }
        let ups = Array(repeating: "..", count: baseComps.count - i)
        return (ups + targetComps[i...]).joined(separator: "/")
    }

    // MARK: Tree

    func bumpTree() {
        decks = Workspace.findDecks(in: root)
        treeVersion += 1
    }

    // MARK: Scanning

    private static func findDecks(in root: URL) -> [URL] {
        allFiles(in: root).filter { ["md", "markdown"].contains($0.pathExtension.lowercased()) }
    }

    private static func findThemes(in root: URL) -> [ThemeFile] {
        allFiles(in: root)
            .filter { $0.pathExtension.lowercased() == "css" }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8),
                      let name = themeName(in: text) else { return nil }
                return ThemeFile(name: name, url: url)
            }
    }

    /// Folder names that never hold deck content and would only slow the scan.
    private static let ignoredDirectories: Set<String> = [
        "node_modules", ".git", ".build", "build", "DerivedData", ".next", "dist", "out", ".venv",
    ]

    /// Every regular file in the workspace, recursively, depth-first and sorted
    /// by path so decks and themes in subfolders are found too.
    private static func allFiles(in root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if ignoredDirectories.contains(url.lastPathComponent) { enumerator.skipDescendants() }
            } else if values?.isRegularFile == true {
                files.append(url)
            }
        }
        // Shallower paths first (so a root deck opens before a subfolder one),
        // then alphabetically.
        return files.sorted { a, b in
            let da = a.pathComponents.count, db = b.pathComponents.count
            if da != db { return da < db }
            return a.path.localizedStandardCompare(b.path) == .orderedAscending
        }
    }

    /// Theme CSS found recursively under a folder, for the headless export,
    /// which has no `Workspace`. Mirrors the in-app recursive theme scan, so a
    /// theme in a subfolder (e.g. `themes/`) is included rather than dropped.
    nonisolated static func themeCSS(in root: URL) -> [String] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var result: [String] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if ignoredDirectories.contains(url.lastPathComponent) { enumerator.skipDescendants() }
            } else if values?.isRegularFile == true, url.pathExtension.lowercased() == "css",
                      let css = try? String(contentsOf: url, encoding: .utf8), themeName(in: css) != nil {
                result.append(css)
            }
        }
        return result
    }

    nonisolated static func themeName(in css: String) -> String? {
        guard let r = css.range(of: #"/\*\s*@theme\s+([A-Za-z0-9_-]+)"#, options: .regularExpression) else { return nil }
        let frag = String(css[r])
        return frag.range(of: #"[A-Za-z0-9_-]+$"#, options: .regularExpression).map { String(frag[$0]) }
    }
}
