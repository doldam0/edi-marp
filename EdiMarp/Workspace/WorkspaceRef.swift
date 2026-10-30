import Foundation

/// A reference to a workspace folder, carried as a window's value so windows
/// restore to their folder. Backed by a security-scoped bookmark (sandbox).
struct WorkspaceRef: Codable, Hashable, Identifiable {
    let bookmark: Data
    var id: Data { bookmark }

    static func make(for url: URL) throws -> WorkspaceRef {
        // A security-scoped bookmark for user-selected folders; falls back to a
        // plain bookmark for paths the app already has access to (e.g. its own
        // container, used by tests).
        if let data = try? url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil, relativeTo: nil) {
            return WorkspaceRef(bookmark: data)
        }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        return WorkspaceRef(bookmark: data)
    }

    /// Resolves the bookmark to a URL. The caller is responsible for balancing
    /// `startAccessingSecurityScopedResource()`.
    func resolve() -> URL? {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                              relativeTo: nil, bookmarkDataIsStale: &stale) { return url }
        return try? URL(resolvingBookmarkData: bookmark, options: [],
                        relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// The folder's display path.
    var displayURL: URL? { resolve() }
}

/// The folders opened recently, newest first, persisted as bookmarks.
enum RecentWorkspaces {
    private static let key = "recentWorkspaces"

    static func all() -> [WorkspaceRef] {
        guard let arr = UserDefaults.standard.array(forKey: key) as? [Data] else { return [] }
        return arr.map { WorkspaceRef(bookmark: $0) }
    }

    static func add(_ ref: WorkspaceRef) {
        let newPath = ref.displayURL?.standardizedFileURL.path
        var arr = all().filter { $0.displayURL?.standardizedFileURL.path != newPath }
        arr.insert(ref, at: 0)
        if arr.count > 10 { arr = Array(arr.prefix(10)) }
        UserDefaults.standard.set(arr.map(\.bookmark), forKey: key)
    }

    static var mostRecent: WorkspaceRef? { all().first }
}
