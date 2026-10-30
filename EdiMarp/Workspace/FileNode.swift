import Foundation

/// A node in the workspace file tree, used by the file explorer. Children are
/// computed lazily so the tree only reads directories it expands.
struct FileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var id: URL { url }
    var name: String { url.lastPathComponent }

    init(url: URL, isDirectory: Bool? = nil) {
        self.url = url
        self.isDirectory = isDirectory ?? ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
    }

    /// `nil` for a leaf (so `OutlineGroup` draws no disclosure triangle),
    /// a sorted list for a directory.
    var children: [FileNode]? {
        guard isDirectory else { return nil }
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return items
            .map { FileNode(url: $0) }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    var ext: String { url.pathExtension.lowercased() }
    var isMarkdown: Bool { ext == "md" || ext == "markdown" }
    var isCSS: Bool { ext == "css" }
    var isImage: Bool { ["png", "jpg", "jpeg", "gif", "svg", "webp", "heic"].contains(ext) }
    var isTextEditable: Bool { isMarkdown || isCSS || ["txt", "json", "yaml", "yml", "html", "js", "ts"].contains(ext) }

    var icon: String {
        if isDirectory { return "folder" }
        if isMarkdown { return "doc.richtext" }
        if isCSS { return "paintbrush" }
        if isImage { return "photo" }
        return "doc"
    }
}
