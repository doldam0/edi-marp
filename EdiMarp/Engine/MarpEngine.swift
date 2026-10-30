import WebKit

struct RenderResult {
    let slides: [String]
    let css: String
    let notes: [[String]]
    let aspect: Double
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

    private let webView: WKWebView
    private var ready = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private override init() {
        webView = WKWebView(frame: .zero, configuration: WebKitShared.configuration())
        super.init()
        webView.navigationDelegate = self
        if let url = Bundle.main.url(forResource: "engine", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
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
        webView.reload()
    }

    private func waitUntilReady() async {
        if ready { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func render(_ source: String) async throws -> RenderResult {
        await waitUntilReady()
        let value = try await webView.callAsyncJavaScript(
            "return EdiEngine.render(source)", arguments: ["source": source], contentWorld: .page)
        guard let dict = value as? [String: Any],
              let slides = dict["slides"] as? [String],
              let css = dict["css"] as? String else { throw EngineError.badResponse }
        let notes = (dict["notes"] as? [[String]]) ?? Array(repeating: [], count: slides.count)
        let aspect = (dict["aspect"] as? Double) ?? 16 / 9
        let theme = (dict["theme"] as? String) ?? "default"
        return RenderResult(slides: slides, css: css, notes: notes, aspect: aspect, theme: theme)
    }

    func exportHTML(_ source: String, title: String) async throws -> String {
        await waitUntilReady()
        let value = try await webView.callAsyncJavaScript(
            "return EdiEngine.exportHtml(source, title)", arguments: ["source": source, "title": title], contentWorld: .page)
        guard let html = value as? String else { throw EngineError.badResponse }
        return html
    }

    func themes() async throws -> [String] {
        await waitUntilReady()
        let value = try await webView.callAsyncJavaScript("return EdiEngine.themes()", arguments: [:], contentWorld: .page)
        return (value as? [String]) ?? []
    }
}
