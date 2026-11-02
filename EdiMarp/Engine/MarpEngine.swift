import WebKit

struct RenderResult {
    let slides: [String]
    let css: String
    let notes: [[String]]
    let aspect: Double
    let width: Double
    let height: Double
    let theme: String
}

enum EngineError: LocalizedError {
    case badResponse
    case missingBundle
    var errorDescription: String? {
        switch self {
        case .badResponse: "렌더 엔진이 알 수 없는 응답을 보냈습니다."
        case .missingBundle: "렌더 엔진 번들(engine.js)을 찾을 수 없습니다."
        }
    }
}

/// Marp runs as JavaScript inside a hidden WKWebView. Swift talks to it only
/// through `callAsyncJavaScript`, so the engine is a pure function of the
/// markdown and never touches app state.
@MainActor
final class MarpEngine: NSObject, WKNavigationDelegate {
    static let shared = MarpEngine()

    /// Posted when the engine bundle is reloaded (dev live reload) so open
    /// sessions can re-render against the new engine.
    static let didReloadNotification = Notification.Name("MarpEngineDidReload")

    private let webView: WKWebView
    private var ready = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let engineURL: URL?
    private var watch: DispatchSourceFileSystemObject?

    private override init() {
        webView = WKWebView(frame: .zero, configuration: WebKitShared.configuration())
        engineURL = Bundle.main.url(forResource: "engine", withExtension: "html")
        super.init()
        webView.navigationDelegate = self
        load()
        startWatchingIfDev()
    }

    private func load() {
        guard let engineURL else { return }
        webView.loadFileURL(engineURL, allowingReadAccessTo: engineURL.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("EdiMarp engine: provisional navigation failed: %@", error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("EdiMarp engine: navigation failed: %@", error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("EdiMarp engine: web content process terminated; reloading")
        ready = false
        load()
    }

    private func waitUntilReady() async {
        if ready { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    // MARK: Live reload

    /// Reloads the engine bundle and notifies observers to re-render.
    func reload() {
        ready = false
        load()
        NotificationCenter.default.post(name: MarpEngine.didReloadNotification, object: nil)
    }

    private func startWatchingIfDev() {
        #if DEBUG
        guard let engineURL else { return }
        let jsURL = engineURL.deletingLastPathComponent().appendingPathComponent("engine.js")
        let fd = open(jsURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            // Vite rewrites the file; re-arm by reloading after a short settle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.reload()
                self?.rearmWatch()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watch = source
        NSLog("EdiMarp engine: watching %@ for live reload", jsURL.path)
        #endif
    }

    private func rearmWatch() {
        #if DEBUG
        // A rename/replace invalidates the fd, so re-establish the watch.
        watch?.cancel()
        watch = nil
        startWatchingIfDev()
        #endif
    }

    // MARK: Calls

    func render(_ source: String, extraThemes: [String] = []) async throws -> RenderResult {
        await waitUntilReady()
        let value = try await webView.callAsyncJavaScript(
            "return EdiEngine.render(source, extraThemes)",
            arguments: ["source": source, "extraThemes": extraThemes], contentWorld: .page)
        guard let dict = value as? [String: Any],
              let slides = dict["slides"] as? [String],
              let css = dict["css"] as? String else { throw EngineError.badResponse }
        let notes = (dict["notes"] as? [[String]]) ?? Array(repeating: [], count: slides.count)
        let width = (dict["width"] as? Double) ?? 1280
        let height = (dict["height"] as? Double) ?? 720
        let aspect = (dict["aspect"] as? Double) ?? width / height
        let theme = (dict["theme"] as? String) ?? "default"
        return RenderResult(slides: slides, css: css, notes: notes, aspect: aspect, width: width, height: height, theme: theme)
    }

    func exportHTML(_ source: String, title: String, extraThemes: [String] = []) async throws -> String {
        await waitUntilReady()
        let value = try await webView.callAsyncJavaScript(
            "return EdiEngine.exportHtml(source, title, extraThemes)",
            arguments: ["source": source, "title": title, "extraThemes": extraThemes], contentWorld: .page)
        guard let html = value as? String else { throw EngineError.badResponse }
        return html
    }

    func themes(extraThemes: [String] = []) async throws -> [String] {
        await waitUntilReady()
        let value = try await webView.callAsyncJavaScript(
            "return EdiEngine.themes(extraThemes)", arguments: ["extraThemes": extraThemes], contentWorld: .page)
        return (value as? [String]) ?? []
    }
}
