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
    @Environment(\.openWindow) private var openWindow

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
        .onAppear {
            DebugScript.run(workspace) {
                PresenterController.shared.start(deck, at: 0)
                openWindow(id: PresenterController.windowID)
            }
        }
    }

    // A manual trailing inspector panel. SwiftUI's `.inspector` drives an
    // Auto Layout constraint loop inside this WindowGroup structure, so the
    // inspector is drawn as an ordinary trailing column instead.
    private var detail: some View {
        HStack(spacing: 0) {
            SplitPane(showLeft: deck.layout != .preview, showRight: deck.layout != .editor) {
                EditorPane(workspace: workspace)
            } right: {
                PreviewView(session: deck)
                    .imageDropTarget(workspace)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if deck.inspectorShown {
                Divider()
                InspectorView(session: deck)
                    .frame(width: 290)
            }
        }
    }
}

/// Editor | preview with a draggable divider. `HSplitView` insisted on a
/// minimum width well above its panes' and overflowed the window, pushing
/// the inspector off the edge and squeezing the sidebar; this one always
/// fits the width it is given.
private struct SplitPane<Left: View, Right: View>: View {
    let showLeft: Bool
    let showRight: Bool
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right

    @AppStorage("splitFraction") private var fraction: Double = 0.47
    @State private var dragStart: Double?
    private let minWidth: CGFloat = 240

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let both = showLeft && showRight
            let leftWidth: CGFloat = both ? min(max(width * fraction, minWidth), max(minWidth, width - minWidth)) : width
            HStack(spacing: 0) {
                if showLeft {
                    left().frame(width: leftWidth, height: geo.size.height)
                }
                if both {
                    Divider()
                        .overlay {
                            Color.clear
                                .frame(width: 9)
                                .contentShape(Rectangle())
                                .onHover { inside in
                                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                                }
                                .gesture(
                                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                        .onChanged { value in
                                            if dragStart == nil { dragStart = fraction }
                                            let start = (dragStart ?? fraction) * width
                                            let next = min(max(start + value.translation.width, minWidth), width - minWidth)
                                            fraction = next / width
                                        }
                                        .onEnded { _ in dragStart = nil }
                                )
                        }
                }
                if showRight {
                    right().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
