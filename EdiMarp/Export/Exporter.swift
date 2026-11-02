import AppKit
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

    /// PDF goes through the marp CLI (headless Chrome) for a true vector PDF with
    /// the theme's gradients intact — WebKit's own PDF drawing cannot.
    static func exportPDF(_ session: DeckSession) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = session.title + ".pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let source = session.deck.source
        let deckURL = session.fileURL
        let root = session.assetRoot
        Task {
            do {
                try await MarpCLI.exportPDF(source: source, deckURL: deckURL, themeRoot: root, output: url)
            } catch {
                presentError(error)
            }
        }
    }

    static func printDeck(_ session: DeckSession) {
        let source = session.deck.source
        let title = session.title
        let deckURL = session.fileURL
        let root = session.assetRoot
        let window = NSApp.keyWindow
        Task {
            do {
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("edimarp-\(UUID().uuidString).pdf")
                defer { try? FileManager.default.removeItem(at: temp) }
                try await MarpCLI.exportPDF(source: source, deckURL: deckURL, themeRoot: root, output: temp)
                guard let document = PDFDocument(url: temp) else { throw CocoaError(.fileReadUnknown) }
                print(document, title: title, parent: window)
            } catch {
                presentError(error)
            }
        }
    }

    private static func print(_ document: PDFDocument, title: String, parent: NSWindow?) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        if let bounds = document.page(at: 0)?.bounds(for: .mediaBox) {
            info.orientation = bounds.width >= bounds.height ? .landscape : .portrait
        }
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else { return }
        operation.jobTitle = title
        if let parent {
            operation.runModal(for: parent, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    private static func presentError(_ error: Error) {
        NSAlert(error: error).runModal()
    }
}

/// `EDIMARP_EXPORT_INPUT=in.md EDIMARP_EXPORT_OUTPUT=out.pdf EdiMarp` runs the
/// same pipeline as the Export menu and quits. Relative images and workspace
/// themes in the deck's folder (recursively) are included.
enum HeadlessExport {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let inPath = env["EDIMARP_EXPORT_INPUT"], let outPath = env["EDIMARP_EXPORT_OUTPUT"] else { return }
        let input = URL(fileURLWithPath: inPath)
        let output = URL(fileURLWithPath: outPath)
        let root = input.deletingLastPathComponent()
        Task { @MainActor in
            do {
                let source = try String(contentsOf: input, encoding: .utf8)
                if output.pathExtension.lowercased() == "pdf" {
                    try await MarpCLI.exportPDF(source: source, deckURL: input, themeRoot: root, output: output)
                } else {
                    let title = input.deletingPathExtension().lastPathComponent
                    var html = try await MarpEngine.shared.exportHTML(source, title: title, extraThemes: Workspace.themeCSS(in: root))
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
