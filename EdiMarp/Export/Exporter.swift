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
        Task {
            do {
                let html = try await MarpEngine.shared.exportHTML(source, title: title)
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
        Task {
            do {
                let render = try await MarpEngine.shared.render(source)
                let document = try await DeckPDFRenderer.shared.makePDF(render)
                guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
            } catch {
                presentError(error)
            }
        }
    }

    static func printDeck(_ session: DeckSession) {
        let source = session.deck.source
        let title = session.title
        let window = NSApp.keyWindow
        Task {
            do {
                let render = try await MarpEngine.shared.render(source)
                try await DeckPDFRenderer.shared.print(render, title: title, parent: window)
            } catch {
                presentError(error)
            }
        }
    }

    private static func presentError(_ error: Error) {
        NSAlert(error: error).runModal()
    }
}

/// Renders every slide to a vector PDF page by loading it into an off-screen
/// slide shell at the deck's point size and capturing it with WebKit's PDF
/// drawing. The pages are merged with PDFKit; printing prints that document.
@MainActor
final class DeckPDFRenderer {
    static let shared = DeckPDFRenderer()

    private let window: NSWindow
    private let host: SlideHostView

    private init() {
        host = SlideHostView()
        host.frame = NSRect(x: 0, y: 0, width: 960, height: 540)
        window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
    }

    /// Page size in points: Marp's convention of 960×540 for 16:9.
    static func pageSize(aspect: Double) -> CGSize {
        aspect >= 1 ? CGSize(width: 960, height: (960 / aspect).rounded()) : CGSize(width: (540 * aspect).rounded(), height: 540)
    }

    func makePDF(_ render: RenderResult) async throws -> PDFDocument {
        let size = Self.pageSize(aspect: render.aspect)
        window.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        let document = PDFDocument()
        for (index, svg) in render.slides.enumerated() {
            try await host.updateAndWait(css: render.css, svg: svg)
            let config = WKPDFConfiguration()
            config.rect = host.bounds
            let data = try await host.pdf(configuration: config)
            guard let page = PDFDocument(data: data)?.page(at: 0) else { throw EngineError.badResponse }
            document.insert(page, at: index)
        }
        return document
    }

    func print(_ render: RenderResult, title: String, parent: NSWindow?) async throws {
        let document = try await makePDF(render)
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
}

/// `EDIMARP_EXPORT_INPUT=in.md EDIMARP_EXPORT_OUTPUT=out.pdf EdiMarp` runs the
/// same pipeline as the Export menu and quits. Environment variables rather
/// than arguments, because NSDocumentController would try to open arguments
/// as documents.
enum HeadlessExport {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let inPath = env["EDIMARP_EXPORT_INPUT"], let outPath = env["EDIMARP_EXPORT_OUTPUT"] else { return }
        let input = URL(fileURLWithPath: inPath)
        let output = URL(fileURLWithPath: outPath)
        Task { @MainActor in
            do {
                let source = try String(contentsOf: input, encoding: .utf8)
                let title = input.deletingPathExtension().lastPathComponent
                if output.pathExtension.lowercased() == "pdf" {
                    let render = try await MarpEngine.shared.render(source)
                    let document = try await DeckPDFRenderer.shared.makePDF(render)
                    guard document.write(to: output) else { throw CocoaError(.fileWriteUnknown) }
                } else {
                    let html = try await MarpEngine.shared.exportHTML(source, title: title)
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
