import SwiftUI

/// Root of a document window: slide sidebar · editor | preview · inspector.
struct DeckWindow: View {
    @ObservedObject var document: DeckDocument
    @StateObject private var session: DeckSession
    @Environment(\.undoManager) private var undoManager
    @State private var columns: NavigationSplitViewVisibility = .all
    private let fileURL: URL?

    init(document: DeckDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _session = StateObject(wrappedValue: DeckSession(document: document))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SlideSidebar(session: session)
                .navigationSplitViewColumnWidth(min: 170, ideal: 230, max: 380)
        } detail: {
            WorkspaceView(session: session)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StatusBar(session: session)
                }
        }
        .inspector(isPresented: $session.inspectorShown) {
            InspectorView(session: session)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .toolbar { DeckToolbar(session: session) }
        .navigationSubtitle(subtitle)
        .focusedSceneObject(session)
        .onAppear {
            session.fileURL = fileURL
            session.editor.externalUndoManager = undoManager
            DebugScript.run(session)
        }
        .onChange(of: fileURL) { _, url in session.fileURL = url }
        .onChange(of: undoManager) { _, manager in session.editor.externalUndoManager = manager }
    }

    private var subtitle: String {
        let theme = ThemeCatalog.label(for: session.deck.theme)
        return "\(session.slideCount)장 · \(theme)"
    }
}

/// Editor and preview side by side with a native split divider.
struct WorkspaceView: View {
    @ObservedObject var session: DeckSession

    var body: some View {
        HSplitView {
            if session.layout != .preview {
                EditorView(session: session)
                    .frame(minWidth: 280, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            }
            if session.layout != .editor {
                PreviewView(session: session)
                    .frame(minWidth: 320, idealWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
