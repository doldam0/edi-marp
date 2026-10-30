import SwiftUI

/// Menu bar. Items route to the focused window's workspace / active deck.
struct DeckCommands: Commands {
    @FocusedObject private var workspace: Workspace?
    @Environment(\.openWindow) private var openWindow

    private var deck: DeckSession? { workspace?.deck }

    var body: some Commands {
        // File: open / create workspaces, recents, save.
        CommandGroup(after: .newItem) {
            Button("워크스페이스 열기…") {
                if let ref = WorkspaceActions.openPanel() { openWindow(value: ref) }
            }
            .keyboardShortcut("o", modifiers: .command)
            Button("새 워크스페이스…") {
                if let ref = WorkspaceActions.newPanel() { openWindow(value: ref) }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Menu("최근 워크스페이스") {
                ForEach(RecentWorkspaces.all()) { ref in
                    if let url = ref.displayURL {
                        Button(url.lastPathComponent) { openWindow(value: ref) }
                    }
                }
            }
            .disabled(RecentWorkspaces.all().isEmpty)
            Divider()
            Button("저장") { workspace?.saveAll() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(workspace == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("프린트…") { if let deck { Exporter.printDeck(deck) } }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(deck == nil)
        }

        CommandGroup(replacing: .importExport) {
            Menu("내보내기") {
                Button("HTML…") { if let deck { Exporter.exportHTML(deck) } }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("PDF…") { if let deck { Exporter.exportPDF(deck) } }
            }
            .disabled(deck == nil)
        }

        CommandMenu("슬라이드") {
            Group {
                Button("새 슬라이드") { deck?.insertSlide() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("슬라이드 복제") { deck?.duplicateSlide() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("슬라이드 삭제") { deck?.deleteSlide() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                Divider()
                Button("위로 이동") { deck?.moveSlide(by: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Button("아래로 이동") { deck?.moveSlide(by: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
                Divider()
                Button("이전 슬라이드") { deck?.previousSlide() }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("다음 슬라이드") { deck?.nextSlide() }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Divider()
                Toggle("리드 (lead)", isOn: classBinding("lead"))
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Toggle("반전 (invert)", isOn: classBinding("invert"))
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            .disabled(deck == nil)
        }

        CommandMenu("삽입") {
            ForEach(Snippets.all) { snippet in
                Button {
                    deck?.insertSnippet(snippet)
                } label: {
                    Label(snippet.title, systemImage: snippet.symbol)
                }
            }
            .disabled(deck == nil)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Button("덱 마크다운 편집") { workspace?.showDeckFile() }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("테마 CSS 편집") { workspace?.showThemeFile() }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("사이드바: 슬라이드 / 파일") {
                if let ws = workspace {
                    ws.sidebarMode = ws.sidebarMode == .slides ? .files : .slides
                    UserDefaults.standard.set(ws.sidebarMode.rawValue, forKey: Pref.sidebarMode)
                }
            }
            .keyboardShortcut("0", modifiers: .command)
            Divider()
            Picker("레이아웃", selection: Binding(
                get: { deck?.layout ?? .split },
                set: { deck?.layout = $0 }
            )) {
                Text("편집기만").tag(DeckSession.Layout.editor).keyboardShortcut("1", modifiers: .command)
                Text("분할").tag(DeckSession.Layout.split).keyboardShortcut("2", modifiers: .command)
                Text("미리보기만").tag(DeckSession.Layout.preview).keyboardShortcut("3", modifiers: .command)
            }
            .pickerStyle(.inline)
            .disabled(deck == nil)
            Divider()
            Toggle("슬라이드 격자", isOn: Binding(
                get: { deck?.previewMode == .grid },
                set: { deck?.previewMode = $0 ? .grid : .focus }
            ))
            .keyboardShortcut("g", modifiers: [.command, .option])
            .disabled(deck == nil)
            Toggle("인스펙터", isOn: Binding(
                get: { deck?.inspectorShown ?? false },
                set: { deck?.inspectorShown = $0 }
            ))
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(deck == nil)
            Divider()
            Button("엔진 다시 로드") { MarpEngine.shared.reload() }
                .keyboardShortcut("r", modifiers: [.command, .control])
        }

        CommandMenu("발표") {
            Group {
                Button("발표 시작") { present(from: 0) }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                Button("현재 슬라이드부터 발표") { present(from: deck?.activeSlide ?? 0) }
                    .keyboardShortcut("p", modifiers: [.command, .option, .shift])
            }
            .disabled(deck == nil)
        }
    }

    private func present(from index: Int) {
        guard let deck else { return }
        PresenterController.shared.start(deck, at: index)
        openWindow(id: PresenterController.windowID)
    }

    private func classBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { deck?.activeSlideModel?.classes.contains(name) ?? false },
            set: { _ in deck?.toggleClass(name) }
        )
    }
}
