import AppKit
import EdiCore

/// `EDIMARP_DEBUG_SCRIPT=1` runs a scripted smoke test against the first
/// document window: every slide operation through the real editor, with
/// undo, and logs each check to the diagnostics output. Inert otherwise.
@MainActor
enum DebugScript {
    static var enabled: Bool { ProcessInfo.processInfo.environment["EDIMARP_DEBUG_SCRIPT"] != nil }
    private static var started = false

    static func run(_ session: DeckSession) {
        guard enabled, !started else { return }
        started = true
        Task { await script(session) }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        Diag.log("CHECK \(ok ? "pass" : "FAIL") \(name) \(detail())")
    }

    private static func settle() async {
        try? await Task.sleep(for: .milliseconds(250))
    }

    /// Polls `condition` up to `timeout`, so a check never races the async
    /// render or the document-text sync.
    private static func waitUntil(_ timeout: Duration = .seconds(3), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func script(_ session: DeckSession) async {
        try? await Task.sleep(for: .seconds(1.5))
        let undo = session.editor.effectiveUndoManager
        let titles = { session.deck.slides.map(\.title) }
        let n0 = session.slideCount
        Diag.log("SCRIPT start: \(n0) slides, titles=\(titles())")

        session.selectSlide(1)
        await settle()
        check("select slide 1", session.activeSlide == 1, "active=\(session.activeSlide) line=\(session.cursorLine)")

        session.insertSlide()
        await settle()
        check("insert slide", session.slideCount == n0 + 1 && session.activeSlide == 2, "count=\(session.slideCount) active=\(session.activeSlide)")
        check("insert caret in new slide", session.deck.lines[session.cursorLine] == "# ", "line=\(session.deck.lines[session.cursorLine])")

        undo?.undo()
        await waitUntil { session.slideCount == n0 }
        check("undo insert", session.slideCount == n0, "count=\(session.slideCount)")
        check("undo keeps text", session.document.text == session.editor.text)

        session.selectSlide(0)
        session.duplicateSlide()
        await settle()
        check("duplicate", session.slideCount == n0 + 1 && titles()[0] == titles()[1], "titles=\(titles().prefix(3))")

        session.deleteSlide()
        await settle()
        check("delete duplicate", session.slideCount == n0, "count=\(session.slideCount) active=\(session.activeSlide)")

        let before = titles()
        session.selectSlide(1)
        session.moveSlide(by: 1)
        await settle()
        check("move down", titles()[2] == before[1] && titles()[1] == before[2] && session.activeSlide == 2, "titles=\(titles().prefix(4))")
        undo?.undo()
        await waitUntil { titles() == before }
        check("undo move", titles() == before)

        session.selectSlide(1)
        session.toggleClass("invert")
        await settle()
        check("toggle invert on", session.activeSlideModel?.classes == ["invert"], "classes=\(session.activeSlideModel?.classes ?? [])")
        session.toggleClass("lead")
        await settle()
        check("toggle lead adds", session.activeSlideModel?.classes == ["invert", "lead"])
        session.toggleClass("invert")
        session.toggleClass("lead")
        await settle()
        check("toggle both off", session.activeSlideModel?.classes.isEmpty == true && session.activeSlideModel?.declared("class") == nil)

        session.setSlideDirective("backgroundColor", "#336699")
        await settle()
        check("set bg", session.activeSlideModel?.effective["backgroundColor"] == "#336699")
        session.setSlideDirective("backgroundColor", nil)
        await settle()
        check("clear bg", session.activeSlideModel?.declared("backgroundColor") == nil)

        session.setGlobalDirective("theme", "paper")
        await waitUntil { session.render?.theme == "paper" }
        check("theme paper", session.deck.theme == "paper" && session.render?.theme == "paper", "deck=\(session.deck.theme) render=\(session.render?.theme ?? "nil")")
        undo?.undo()
        await waitUntil { session.render?.theme == "noir" }
        check("undo theme", session.deck.theme == "noir" && session.render?.theme == "noir")

        session.goToLine(10)
        await settle()
        check("go to line", session.cursorLine == 10, "line=\(session.cursorLine) slide=\(session.activeSlide)")

        session.selectSlide(n0 - 1)
        await settle()
        check("select last", session.activeSlide == n0 - 1)
        session.nextSlide()
        await settle()
        check("next clamps", session.activeSlide == n0 - 1)

        session.previewMode = .grid
        session.inspectorShown = true
        session.layout = .preview
        try? await Task.sleep(for: .seconds(1))
        check("grid+inspector+preview layout", session.previewMode == .grid && session.inspectorShown && session.layout == .preview)
        session.selectSlide(2)
        await settle()
        check("select while editor hidden", session.activeSlide == 2)
        session.layout = .split
        session.previewMode = .focus

        session.insertSnippet(Snippets.all[0])
        await waitUntil { session.document.text.contains("![width:600px](image.png)") }
        check("snippet inserted", session.document.text.contains("![width:600px](image.png)"))
        undo?.undo()
        await waitUntil { !session.document.text.contains("![width:600px](image.png)") }
        check("undo snippet", !session.document.text.contains("![width:600px](image.png)"), "tail=\(session.document.text.suffix(40).replacingOccurrences(of: "\n", with: "\\n"))")

        check("doc == editor", session.document.text == session.editor.text)
        check("render fresh", session.render?.slides.count == session.slideCount, "render=\(session.render?.slides.count ?? -1) deck=\(session.slideCount)")
        Diag.log("SCRIPT done")
    }
}
