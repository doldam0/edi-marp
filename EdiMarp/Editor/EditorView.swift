import SwiftUI

/// Hosts the session's text view. The controller outlives the view so the
/// editor keeps its undo stack and scroll position when the panel is hidden.
struct EditorView: NSViewRepresentable {
    @ObservedObject var session: DeckSession
    @AppStorage(Pref.editorFontSize) private var fontSize = 13.0
    @AppStorage(Pref.showGutter) private var showGutter = true
    @Environment(\.undoManager) private var undoManager

    func makeNSView(context: Context) -> NSScrollView {
        session.editor.scrollView
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        let editor = session.editor
        if let undoManager { editor.externalUndoManager = undoManager }
        if editor.fontSize != CGFloat(fontSize) { editor.fontSize = CGFloat(fontSize).clamped(10, 28) }
        if editor.showGutter != showGutter { editor.showGutter = showGutter }
        if editor.activeSlide != session.activeSlide { editor.activeSlide = session.activeSlide }
    }
}
