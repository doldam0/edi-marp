import WebKit

enum WebKitShared {
    static let processPool = WKProcessPool()

    static func configuration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.processPool = processPool
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        return config
    }

    static var slideShellURL: URL? {
        Bundle.main.url(forResource: "slide", withExtension: "html")
    }
}

/// Forwards script messages without retaining the web view (WebKit retains
/// its handlers strongly, which would otherwise leak every view).
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// A web view that shows exactly one Marp slide (an inline SVG) on a
/// transparent background. It loads the static `slide.html` shell once and
/// receives CSS/SVG updates through `window.edi.update`.
@MainActor
final class SlideHostView: WKWebView, WKScriptMessageHandler, WKNavigationDelegate {
    var onLine: ((Int) -> Void)?
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    /// When true the view ignores the mouse so the SwiftUI row behind it gets clicks.
    var passthrough = false
    /// Workspace folder used to serve relative image paths via `ediasset://`.
    var assetRoot: URL?

    private let assetHandler = AssetSchemeHandler()
    private var ready = false
    private var pending: (css: String, svg: String, interactive: Bool)?
    private var last: (css: String, svg: String, interactive: Bool)?
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []

    init() {
        let config = WebKitShared.configuration()
        config.setURLSchemeHandler(assetHandler, forURLScheme: AssetSchemeHandler.scheme)
        super.init(frame: .zero, configuration: config)
        assetHandler.host = self
        config.userContentController.add(WeakScriptHandler(self), name: "edi")
        navigationDelegate = self
        allowsMagnification = false
        setValue(false, forKey: "drawsBackground")
        underPageBackgroundColor = .clear
        if let url = WebKitShared.slideShellURL {
            loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        // Let the SwiftUI preview handle image drops rather than the web view
        // trying to navigate to the dropped file.
        unregisterDraggedTypes()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        passthrough ? nil : super.hitTest(point)
    }

    /// Rewrites relative image paths to the asset scheme when a workspace root
    /// is set, so the slide can show images stored beside the deck.
    private func prepared(_ svg: String) -> String {
        assetRoot != nil ? AssetRewriter.toScheme(svg) : svg
    }

    func update(css: String, rawSVG: String, interactive: Bool) {
        update(css: css, svg: prepared(rawSVG), interactive: interactive)
    }

    func update(css: String, svg: String, interactive: Bool) {
        guard ready else { pending = (css, svg, interactive); return }
        if let last, last.css == css, last.svg == svg, last.interactive == interactive { return }
        last = (css, svg, interactive)
        callAsyncJavaScript("window.edi.update(css, svg, interactive)",
                            arguments: ["css": css, "svg": svg, "interactive": interactive],
                            in: nil, in: .page) { _ in }
    }

    /// Suspends until the shell page has loaded.
    func waitUntilReady() async {
        if ready { return }
        await withCheckedContinuation { readyWaiters.append($0) }
    }

    /// Sets the slide and returns once fonts and layout have settled (PDF capture).
    func updateAndWait(css: String, svg rawSVG: String) async throws {
        await waitUntilReady()
        let svg = prepared(rawSVG)
        last = (css, svg, false)
        _ = try await callAsyncJavaScript("return window.edi.update(css, svg, false)",
                                          arguments: ["css": css, "svg": svg], contentWorld: .page)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            readyWaiters.forEach { $0.resume() }
            readyWaiters.removeAll()
            if let p = pending { pending = nil; update(css: p.css, svg: p.svg, interactive: p.interactive) }
        case "line":
            if let line = body["line"] as? Int { onLine?(line) } else if let d = body["line"] as? Double { onLine?(Int(d)) }
        case "click":
            onClick?()
        case "dblclick":
            onDoubleClick?()
        default:
            break
        }
    }
}
