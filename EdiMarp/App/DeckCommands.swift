import SwiftUI

/// Menu bar. Every item routes to the focused window's session.
struct DeckCommands: Commands {
    @FocusedObject private var session: DeckSession?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.newDocument) private var newDocument

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("프린트…") { if let session { Exporter.printDeck(session) } }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(session == nil)
        }

        CommandGroup(replacing: .importExport) {
            Menu("내보내기") {
                Button("HTML…") { if let session { Exporter.exportHTML(session) } }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("PDF…") { if let session { Exporter.exportPDF(session) } }
            }
            .disabled(session == nil)
        }

        CommandMenu("슬라이드") {
            Group {
            Button("새 슬라이드") { session?.insertSlide() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("슬라이드 복제") { session?.duplicateSlide() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("슬라이드 삭제") { session?.deleteSlide() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
            Divider()
            Button("위로 이동") { session?.moveSlide(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
            Button("아래로 이동") { session?.moveSlide(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
            Divider()
            Button("이전 슬라이드") { session?.previousSlide() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("다음 슬라이드") { session?.nextSlide() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Divider()
            Toggle("리드 (lead)", isOn: classBinding("lead"))
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Toggle("반전 (invert)", isOn: classBinding("invert"))
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            .disabled(session == nil)
        }

        CommandMenu("삽입") {
            ForEach(Snippets.all) { snippet in
                Button {
                    session?.insertSnippet(snippet)
                } label: {
                    Label(snippet.title, systemImage: snippet.symbol)
                }
            }
            .disabled(session == nil)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Picker("레이아웃", selection: Binding(
                get: { session?.layout ?? .split },
                set: { session?.layout = $0 }
            )) {
                Text("편집기만").tag(DeckSession.Layout.editor).keyboardShortcut("1", modifiers: .command)
                Text("분할").tag(DeckSession.Layout.split).keyboardShortcut("2", modifiers: .command)
                Text("미리보기만").tag(DeckSession.Layout.preview).keyboardShortcut("3", modifiers: .command)
            }
            .pickerStyle(.inline)
            .disabled(session == nil)
            Divider()
            Toggle("슬라이드 격자", isOn: Binding(
                get: { session?.previewMode == .grid },
                set: { session?.previewMode = $0 ? .grid : .focus }
            ))
            .keyboardShortcut("g", modifiers: [.command, .option])
            .disabled(session == nil)
            Toggle("인스펙터", isOn: Binding(
                get: { session?.inspectorShown ?? false },
                set: { session?.inspectorShown = $0 }
            ))
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(session == nil)
            Divider()
        }

        CommandMenu("발표") {
            Group {
                Button("발표 시작") { present(from: 0) }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                Button("현재 슬라이드부터 발표") { present(from: session?.activeSlide ?? 0) }
                    .keyboardShortcut("p", modifiers: [.command, .option, .shift])
            }
            .disabled(session == nil)
        }

        CommandGroup(replacing: .help) {
            Button("EdiMarp 둘러보기") {
                newDocument { DeckDocument(text: Templates.welcome) }
            }
        }
    }

    private func present(from index: Int) {
        guard let session else { return }
        PresenterController.shared.start(session, at: index)
        openWindow(id: PresenterController.windowID)
    }

    private func classBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { session?.activeSlideModel?.classes.contains(name) ?? false },
            set: { _ in session?.toggleClass(name) }
        )
    }
}
