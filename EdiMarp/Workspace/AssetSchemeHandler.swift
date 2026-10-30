import WebKit
import UniformTypeIdentifiers

/// Serves workspace files to the slide WebViews under the `ediasset` scheme, so
/// a deck can reference images by their path relative to the workspace root.
/// Each slide view owns one handler that reads the view's current `assetRoot`.
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "ediasset"
    weak var host: SlideHostView?

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let root = host?.assetRoot, let url = task.request.url else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        // ediasset:///relative/path -> <root>/relative/path, confined to root.
        var rel = (url.path.removingPercentEncoding ?? url.path)
        while rel.hasPrefix("/") { rel.removeFirst() }
        let fileURL = root.appendingPathComponent(rel).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard fileURL.path == rootPath || fileURL.path.hasPrefix(rootPath + "/"),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Rewrites relative asset references in rendered slide HTML. Marp emits image
/// paths exactly as written in the markdown; the preview maps them to the
/// `ediasset` scheme, and the exporter inlines them as data URIs.
enum AssetRewriter {
    // Matches src / href / xlink:href whose value is a relative path (not an
    // absolute URL, data URI, fragment, or already-rewritten scheme).
    private static let attr = try! NSRegularExpression(
        pattern: #"(\bsrc|\bhref|\bxlink:href)=(["'])(?!https?:|data:|ediasset:|#|/)([^"']+)\2"#)

    static func toScheme(_ html: String) -> String {
        rewrite(html) { _, path, quote in
            let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            return "=\(quote)\(AssetSchemeHandler.scheme):///\(encoded)\(quote)"
        }
    }

    /// Replaces relative image refs with data URIs read from `root`.
    static func inlineDataURIs(_ html: String, root: URL) -> String {
        rewrite(html) { _, path, quote in
            let decoded = path.removingPercentEncoding ?? path
            let fileURL = root.appendingPathComponent(decoded)
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            return "=\(quote)data:\(mime);base64,\(data.base64EncodedString())\(quote)"
        }
    }

    /// `replace(attr, path, quote) -> replacement for the "=\"path\"" part`, or
    /// nil to leave the match unchanged.
    private static func rewrite(_ html: String, _ replace: (String, String, String) -> String?) -> String {
        let ns = html as NSString
        let result = NSMutableString(string: html)
        let matches = attr.matches(in: html, range: NSRange(location: 0, length: ns.length))
        for m in matches.reversed() {
            let attrName = ns.substring(with: m.range(at: 1))
            let quote = ns.substring(with: m.range(at: 2))
            let path = ns.substring(with: m.range(at: 3))
            guard let repl = replace(attrName, path, quote) else { continue }
            // Replace only the "=<quote>...<quote>" tail, keeping the attr name.
            let tailRange = NSRange(location: m.range(at: 1).location + (attrName as NSString).length,
                                    length: NSMaxRange(m.range) - (m.range(at: 1).location + (attrName as NSString).length))
            result.replaceCharacters(in: tailRange, with: repl)
        }
        return result as String
    }
}
