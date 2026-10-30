import SwiftUI

/// SwiftUI wrapper around `SlideHostView`. Pass the shared theme CSS and one
/// slide's SVG; the view keeps its aspect ratio through `aspect`.
struct SlideWebView: NSViewRepresentable {
    var css: String
    var svg: String
    var interactive = false
    var passthrough = false
    var assetRoot: URL? = nil
    var onLine: ((Int) -> Void)? = nil
    var onClick: (() -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> SlideHostView {
        SlideHostView()
    }

    func updateNSView(_ view: SlideHostView, context: Context) {
        view.assetRoot = assetRoot
        view.passthrough = passthrough
        view.onLine = onLine
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.update(css: css, rawSVG: svg, interactive: interactive)
    }
}

/// A slide card: the web view on a rounded, shadowed backing so the slide
/// reads as an object on the canvas.
struct SlideCard: View {
    @ObservedObject var session: DeckSession
    var index: Int
    var interactive = false
    var passthrough = true
    var onLine: ((Int) -> Void)? = nil
    var onClick: (() -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil
    var cornerRadius: CGFloat = 6
    var shadow: CGFloat = 14

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.22), radius: shadow, y: shadow / 2)
            if let render = session.render, let svg = session.svg(for: index) {
                SlideWebView(css: render.css, svg: svg, interactive: interactive, passthrough: passthrough,
                             assetRoot: session.assetRoot,
                             onLine: onLine, onClick: onClick, onDoubleClick: onDoubleClick)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .aspectRatio(session.aspect, contentMode: .fit)
    }
}
