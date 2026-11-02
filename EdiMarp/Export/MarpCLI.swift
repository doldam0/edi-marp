import Foundation

/// Drives the bundled/installed `marp` CLI to produce PDFs. The CLI renders
/// through headless Chrome, so it yields a true vector PDF with the theme's
/// gradients intact — which WebKit's own PDF drawing cannot. The live preview
/// and HTML export still use the in-process marp-core engine; only PDF (and
/// print) go through the CLI.
enum MarpCLI {
    enum MarpError: LocalizedError {
        case marpNotFound
        case chromeNotFound
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .marpNotFound:
                "marp-cli를 찾을 수 없습니다. `npm i -g @marp-team/marp-cli` 로 설치하거나 앱에 동봉해야 합니다."
            case .chromeNotFound:
                "PDF 렌더링에 필요한 Chrome을 찾을 수 없습니다. Google Chrome을 설치해 주세요."
            case .failed(let message):
                "PDF 변환에 실패했습니다.\n\(message)"
            }
        }
    }

    /// Candidate locations for the `marp` executable: a copy bundled in the app
    /// first (for distribution), then the usual Homebrew / npm global paths.
    private static func findMarp() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("marp-cli/marp"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        let candidates = [
            "/opt/homebrew/bin/marp",
            "/usr/local/bin/marp",
            "/opt/homebrew/lib/node_modules/@marp-team/marp-cli/marp-cli.js",
        ]
        return candidates.lazy.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func findChrome() -> URL? {
        let candidates = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        ]
        return candidates.lazy.map(URL.init(fileURLWithPath:)).first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Converts `source` to a PDF at `output`. The markdown is written to a
    /// temporary file beside `deckURL` so relative image paths resolve, and
    /// `themeRoot` (the workspace folder) is handed to `--theme-set` so a
    /// `theme:` pointing at a workspace CSS — even one in a subfolder — is found.
    static func exportPDF(source: String, deckURL: URL, themeRoot: URL?, output: URL) async throws {
        guard let marp = findMarp() else { throw MarpError.marpNotFound }
        guard let chrome = findChrome() else { throw MarpError.chromeNotFound }

        let directory = deckURL.deletingLastPathComponent()
        let tempURL = directory.appendingPathComponent(".ediexport-\(UUID().uuidString).md")
        try source.data(using: .utf8)?.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var arguments = [tempURL.path, "--pdf", "--allow-local-files", "--no-config-file", "-o", output.path]
        if let themeRoot { arguments += ["--theme-set", themeRoot.path] }

        try await run(marp, arguments: arguments, directory: directory, chrome: chrome)
    }

    private static func run(_ executable: URL, arguments: [String], directory: URL, chrome: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = directory

            var environment = ProcessInfo.processInfo.environment
            environment["CHROME_PATH"] = chrome.path
            // A GUI app inherits a bare PATH; the `marp` shim is run through
            // `/usr/bin/env node`, so Node and the CLI must be discoverable.
            let extraPath = "/opt/homebrew/bin:/usr/local/bin:/opt/homebrew/opt/node/bin"
            environment["PATH"] = extraPath + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
            process.environment = environment

            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = Pipe()
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: data, encoding: .utf8) ?? "알 수 없는 오류 (코드 \(finished.terminationStatus))"
                    continuation.resume(throwing: MarpError.failed(message))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
