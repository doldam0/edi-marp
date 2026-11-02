import AppKit
import WebKit
import PDFKit
import UniformTypeIdentifiers

@MainActor
enum Exporter {
    static func exportHTML(_ session: DeckSession) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = session.title + ".html"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let source = session.deck.source
        let title = session.title
        let themes = session.extraThemes
        let root = session.assetRoot
        Task {
            do {
                var html = try await MarpEngine.shared.exportHTML(source, title: title, extraThemes: themes)
                if let root { html = AssetRewriter.inlineDataURIs(html, root: root) }
                try html.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                presentError(error)
            }
        }
    }

    static func exportPDF(_ session: DeckSession) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = session.title + ".pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let source = session.deck.source
        let themes = session.extraThemes
        let root = session.assetRoot
        Task {
            do {
                let r = try await MarpEngine.shared.render(source, extraThemes: themes)
                let document = try await DeckPDFRenderer.shared.makePDF(r, assetRoot: root)
                guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
            } catch {
                presentError(error)
            }
        }
    }

    static func printDeck(_ session: DeckSession) {
        let source = session.deck.source
        let title = session.title
        let themes = session.extraThemes
        let root = session.assetRoot
        let window = NSApp.keyWindow
        Task {
            do {
                let r = try await MarpEngine.shared.render(source, extraThemes: themes)
                try await DeckPDFRenderer.shared.print(r, title: title, assetRoot: root, parent: window)
            } catch {
                presentError(error)
            }
        }
    }

    private static func presentError(_ error: Error) {
        NSAlert(error: error).runModal()
    }
}

/// Renders every slide to a vector PDF page. Each slide is the same plain
/// `<section>` HTML the live preview uses, loaded into an off-screen web view
/// at its natural CSS size and captured with WebKit's PDF drawing; the pages
/// are merged with PDFKit.
///
/// HTML sections at natural size, with no CSS `transform`: the preview scales
/// each section with `transform: scale()` to fit its card, but a
/// transform-scaled section loses its backgrounds and clips its overflow when
/// captured to PDF. Capturing at 1:1 avoids that. (Inline SVG is not used here
/// because WKWebView fails to paint a `<foreignObject>`'s flex content.)
@MainActor
final class DeckPDFRenderer: NSObject, WKNavigationDelegate {
    static let shared = DeckPDFRenderer()

    private let window: NSWindow
    private let webView: WKWebView
    private var navWaiter: CheckedContinuation<Void, Never>?

    private override init() {
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720), configuration: WebKitShared.configuration())
        window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        window.contentView = webView
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            navWaiter?.resume()
            navWaiter = nil
        }
    }

    func makePDF(_ render: RenderResult, assetRoot: URL? = nil) async throws -> PDFDocument {
        let size = CGSize(width: render.width, height: render.height)
        window.setContentSize(size)
        webView.frame = NSRect(origin: .zero, size: size)
        let document = PDFDocument()
        for (index, rawSection) in render.slides.enumerated() {
            let section = assetRoot.map { AssetRewriter.inlineDataURIs(rawSection, root: $0) } ?? rawSection
            await load(Self.page(css: render.css, section: section))
            try await waitForFonts()
            let config = WKPDFConfiguration()
            config.rect = CGRect(origin: .zero, size: size)
            let data = try await webView.pdf(configuration: config)
            guard let page = PDFDocument(data: data)?.page(at: 0) else { throw EngineError.badResponse }
            document.insert(page, at: index)
        }
        return document
    }

    func print(_ render: RenderResult, title: String, assetRoot: URL? = nil, parent: NSWindow?) async throws {
        let document = try await makePDF(render, assetRoot: assetRoot)
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.orientation = render.aspect >= 1 ? .landscape : .portrait
        guard let op = document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else { return }
        op.jobTitle = title
        if let parent {
            op.runModal(for: parent, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }

    private func load(_ html: String) async {
        await withCheckedContinuation { continuation in
            navWaiter = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    private func waitForFonts() async throws {
        _ = try await webView.callAsyncJavaScript(
            "return (document.fonts ? document.fonts.ready : Promise.resolve()).then(() => new Promise((r) => setTimeout(r, 40)))",
            arguments: [:], contentWorld: .page)
    }

    /// One slide as a full page: the theme CSS plus the plain `<section>`, drawn
    /// at its natural size (the web view is sized to match), so the capture is
    /// 1:1 with no scaling.
    private static func page(css: String, section: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <style>\(css)</style>
        <style>html,body{margin:0;padding:0;background:transparent}
        div.marpit{position:absolute;top:0;left:0}</style>
        </head><body><div class="marpit">\(section)</div></body></html>
        """
    }
}

/// `EDIMARP_EXPORT_INPUT=in.md EDIMARP_EXPORT_OUTPUT=out.pdf EdiMarp` runs the
/// same pipeline as the Export menu and quits. Sibling `.css` theme files and
/// relative images in the deck's folder are included.
enum HeadlessExport {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let inPath = env["EDIMARP_EXPORT_INPUT"], let outPath = env["EDIMARP_EXPORT_OUTPUT"] else { return }
        let input = URL(fileURLWithPath: inPath)
        let output = URL(fileURLWithPath: outPath)
        let root = input.deletingLastPathComponent()
        let themes = Workspace.themeCSS(in: root)
        Task { @MainActor in
            do {
                let source = try String(contentsOf: input, encoding: .utf8)
                let title = input.deletingPathExtension().lastPathComponent
                if output.pathExtension.lowercased() == "pdf" {
                    let r = try await MarpEngine.shared.render(source, extraThemes: themes)
                    let document = try await DeckPDFRenderer.shared.makePDF(r, assetRoot: root)
                    guard document.write(to: output) else { throw CocoaError(.fileWriteUnknown) }
                } else {
                    var html = try await MarpEngine.shared.exportHTML(source, title: title, extraThemes: themes)
                    html = AssetRewriter.inlineDataURIs(html, root: root)
                    try html.write(to: output, atomically: true, encoding: .utf8)
                }
                FileHandle.standardError.write(Data("exported \(output.path)\n".utf8))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("export failed: \(error)\n".utf8))
                exit(1)
            }
        }
    }
}
