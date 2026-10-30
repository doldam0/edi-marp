import SwiftUI

/// Lazily builds the `Workspace` for a window's `WorkspaceRef`.
@MainActor
final class WorkspaceHolder: ObservableObject {
    @Published var workspace: Workspace?
    @Published var failed = false

    func load(_ ref: WorkspaceRef?) {
        guard workspace == nil, let ref else { return }
        if let ws = Workspace(ref: ref) { workspace = ws } else { failed = true }
    }
}

/// A window. With a resolvable `WorkspaceRef` it shows the workspace; otherwise
/// a welcome screen to open or create one.
struct WorkspaceWindow: View {
    @Binding var ref: WorkspaceRef?
    @StateObject private var holder = WorkspaceHolder()

    var body: some View {
        Group {
            if let workspace = holder.workspace {
                WorkspaceContainer(workspace: workspace)
            } else {
                WelcomeView(failed: holder.failed) { ref = $0 }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear { holder.load(ref) }
        .onChange(of: ref) { _, r in holder.load(r) }
    }
}

/// Observes the workspace so that switching the active deck (which publishes a
/// new `deckURL`) rebuilds the deck-bound UI with the right session.
private struct WorkspaceContainer: View {
    @ObservedObject var workspace: Workspace
    var body: some View {
        WorkspaceRoot(workspace: workspace, deck: workspace.deck)
    }
}

/// The full workspace UI, rebuilt (via `.id(deckURL)`) when the active deck
/// changes so the deck-bound views observe the right session.
private struct WorkspaceRoot: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var deck: DeckSession
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            WorkspaceSidebar(workspace: workspace)
                .navigationSplitViewColumnWidth(min: 180, ideal: 244, max: 400)
        } detail: {
            detail
                .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar(session: deck) }
        }
        .toolbar { DeckToolbar(workspace: workspace) }
        .navigationTitle(deck.title)
        .navigationSubtitle("\(deck.slideCount)장 · \(ThemeCatalog.label(for: deck.deck.theme)) · \(workspace.root.lastPathComponent)")
        .focusedSceneObject(workspace)
        .onAppear { DebugScript.run(workspace) }
    }

    // A manual trailing inspector panel. SwiftUI's `.inspector` drives an
    // Auto Layout constraint loop inside this WindowGroup structure, so the
    // inspector is drawn as an ordinary trailing column instead.
    private var detail: some View {
        HStack(spacing: 0) {
            HSplitView {
                if deck.layout != .preview {
                    EditorPane(workspace: workspace)
                        .frame(minWidth: 320, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                }
                if deck.layout != .editor {
                    PreviewView(session: deck)
                        .frame(minWidth: 320, idealWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if deck.inspectorShown {
                Divider()
                InspectorView(session: deck)
                    .frame(width: 290)
            }
        }
    }
}

/// Open-or-create screen for a window without a workspace.
struct WelcomeView: View {
    var failed = false
    let onOpen: (WorkspaceRef) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("edi · marp")
                .font(.largeTitle.weight(.semibold))
            Text("Marp 슬라이드 워크스페이스")
                .foregroundStyle(.secondary)
            if failed {
                Label("워크스페이스 폴더를 열 수 없습니다.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Button {
                    if let ref = WorkspaceActions.openPanel() { onOpen(ref) }
                } label: {
                    Label("워크스페이스 열기", systemImage: "folder")
                }
                .controlSize(.large)
                Button {
                    if let ref = WorkspaceActions.newPanel() { onOpen(ref) }
                } label: {
                    Label("새 워크스페이스", systemImage: "plus")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
            if !RecentWorkspaces.all().isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("최근 항목").font(.caption).foregroundStyle(.secondary)
                    ForEach(RecentWorkspaces.all().prefix(5)) { ref in
                        if let url = ref.displayURL {
                            Button {
                                onOpen(ref)
                            } label: {
                                Label(url.lastPathComponent, systemImage: "clock")
                                    .font(.callout)
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Folder pickers for opening and creating workspaces, shared by the welcome
/// screen and the menu commands.
enum WorkspaceActions {
    static func openPanel() -> WorkspaceRef? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "열기"
        panel.message = "Marp 워크스페이스 폴더를 선택하세요"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try? WorkspaceRef.make(for: url)
    }

    static func newPanel() -> WorkspaceRef? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "새 프레젠테이션"
        panel.prompt = "만들기"
        panel.message = "새 워크스페이스 폴더를 만들 위치와 이름을 정하세요"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let deck = url.appendingPathComponent("deck.md")
        if !FileManager.default.fileExists(atPath: deck.path) {
            try? Templates.welcome.data(using: .utf8)?.write(to: deck, options: .atomic)
        }
        return try? WorkspaceRef.make(for: url)
    }
}
