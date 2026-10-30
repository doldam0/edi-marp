import SwiftUI

/// A disclosure tree of the workspace folder. Clicking a file opens it as the
/// editor's current file (markdown also becomes the active deck); images are
/// revealed in Finder. The active deck and themes are marked.
struct FileExplorer: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        List {
            // `treeVersion` forces a re-read after files are created/renamed.
            OutlineGroup(workspace.rootNode.children ?? [], id: \.id, children: \.children) { node in
                row(node)
            }
            .id(workspace.treeVersion)
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 24)
    }

    private func row(_ node: FileNode) -> some View {
        let isActiveDeck = node.url == workspace.deckURL
        let isCurrent = node.url == workspace.currentFileURL && !workspace.showThemePrompt
        let isTheme = workspace.themeFiles.contains { $0.url == node.url }
        return HStack(spacing: 6) {
            Image(systemName: node.icon)
                .foregroundStyle(isActiveDeck ? Color.accentColor : (isTheme ? Color.purple : .secondary))
                .frame(width: 16)
            Text(node.name)
                .lineLimit(1)
                .fontWeight(isActiveDeck ? .semibold : .regular)
            Spacer(minLength: 0)
            if isActiveDeck {
                Image(systemName: "play.rectangle.fill").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.14) : Color.clear)
        .onTapGesture { if !node.isDirectory { workspace.open(node.url) } }
    }
}
