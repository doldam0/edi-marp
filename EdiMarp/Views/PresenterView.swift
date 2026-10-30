import SwiftUI
import AppKit

/// App-wide presenter state: which session is on stage and where it is.
@MainActor
final class PresenterController: ObservableObject {
    static let shared = PresenterController()
    static let windowID = "presenter"

    @Published var session: DeckSession?
    @Published var index = 0
    @Published var showNotes = false

    func start(_ session: DeckSession, at index: Int) {
        self.session = session
        self.index = index
    }

    var count: Int { session?.slideCount ?? 0 }

    func go(_ delta: Int) {
        guard count > 0 else { return }
        index = max(0, min(count - 1, index + delta))
    }

    func stop() {
        session = nil
    }
}

struct PresenterView: View {
    @EnvironmentObject private var presenter: PresenterController
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let session = presenter.session {
                PresenterStage(session: session, presenter: presenter)
            } else {
                ContentUnavailableView("발표할 덱이 없습니다", systemImage: "play.slash", description: Text("문서 창에서 ⌥⌘P 로 발표를 시작하세요."))
            }
        }
        .background(Color.black)
        .background(WindowAccessor { window in
            window.backgroundColor = .black
            if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        })
    }
}

private struct PresenterStage: View {
    @ObservedObject var session: DeckSession
    @ObservedObject var presenter: PresenterController
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if let render = session.render, let svg = session.svg(for: presenter.index) {
                    SlideWebView(css: render.css, svg: svg)
                        .aspectRatio(render.aspect, contentMode: .fit)
                        .onTapGesture { presenter.go(1) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if presenter.showNotes {
                NotesPane(session: session, presenter: presenter)
                    .frame(width: 320)
                    .transition(.move(edge: .trailing))
            }
        }
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: geo.size.width * CGFloat(presenter.index + 1) / CGFloat(max(1, presenter.count)), height: 2)
            }
            .frame(height: 2)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.rightArrow) { presenter.go(1); return .handled }
        .onKeyPress(.downArrow) { presenter.go(1); return .handled }
        .onKeyPress(.space) { presenter.go(1); return .handled }
        .onKeyPress(.leftArrow) { presenter.go(-1); return .handled }
        .onKeyPress(.upArrow) { presenter.go(-1); return .handled }
        .onKeyPress(.home) { presenter.index = 0; return .handled }
        .onKeyPress(.end) { presenter.index = max(0, presenter.count - 1); return .handled }
        .onKeyPress(characters: .init(charactersIn: "jlJL")) { _ in presenter.go(1); return .handled }
        .onKeyPress(characters: .init(charactersIn: "hkHK")) { _ in presenter.go(-1); return .handled }
        .onKeyPress(characters: .init(charactersIn: "nN")) { _ in
            withAnimation(.easeOut(duration: 0.2)) { presenter.showNotes.toggle() }
            return .handled
        }
        .onKeyPress(.escape) {
            session.selectSlide(presenter.index)
            dismissWindow(id: PresenterController.windowID)
            presenter.stop()
            return .handled
        }
    }
}

private struct NotesPane: View {
    @ObservedObject var session: DeckSession
    @ObservedObject var presenter: PresenterController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(presenter.index + 1) / \(presenter.count)")
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
            let notes = session.notes(for: presenter.index)
            ScrollView {
                Text(notes.isEmpty ? "발표자 노트가 없습니다.\n슬라이드에 <!-- 메모 --> 를 적어 보세요." : notes.joined(separator: "\n\n"))
                    .font(.body)
                    .foregroundStyle(notes.isEmpty ? Color.white.opacity(0.45) : Color.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if presenter.index + 1 < presenter.count, let render = session.render, let next = session.svg(for: presenter.index + 1) {
                Text("다음").font(.caption).foregroundStyle(.white.opacity(0.6))
                SlideWebView(css: render.css, svg: next, passthrough: true)
                    .aspectRatio(render.aspect, contentMode: .fit)
                    .background(Color.white.opacity(0.08))
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.06))
    }
}

/// Gives SwiftUI code a hook on the hosting NSWindow.
struct WindowAccessor: NSViewRepresentable {
    var configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { configure(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
