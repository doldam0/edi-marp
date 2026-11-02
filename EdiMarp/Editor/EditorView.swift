import SwiftUI

/// Hosts one `EditorController`'s text view. The controller outlives the view,
/// so each file keeps its own buffer, undo stack, and scroll position as the
/// editor pane switches between files.
struct EditorView: NSViewRepresentable {
    let controller: EditorController
    @AppStorage(Pref.editorFontSize) private var fontSize = 13.0
    @AppStorage(Pref.showGutter) private var showGutter = true
    @AppStorage(Pref.spellCheck) private var spellCheck = true

    func makeNSView(context: Context) -> NSScrollView {
        controller.scrollView
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        if controller.fontSize != CGFloat(fontSize) { controller.fontSize = CGFloat(fontSize).clamped(10, 28) }
        if controller.showGutter != showGutter { controller.showGutter = showGutter }
        if controller.spellCheck != spellCheck { controller.spellCheck = spellCheck }
    }
}
