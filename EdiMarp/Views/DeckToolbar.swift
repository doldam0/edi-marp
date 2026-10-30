import SwiftUI

struct DeckToolbar: ToolbarContent {
    @ObservedObject var session: DeckSession
    @Environment(\.openWindow) private var openWindow

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                session.insertSlide()
            } label: {
                Label("새 슬라이드", systemImage: "plus.rectangle.on.rectangle")
            }
            .help("현재 슬라이드 아래에 새 슬라이드 (⌘⏎)")

            Picker("레이아웃", selection: $session.layout) {
                ForEach(DeckSession.Layout.allCases) { layout in
                    Label(layout.title, systemImage: layout.symbol).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .help("편집기 · 분할 · 미리보기 (⌘1 · ⌘2 · ⌘3)")

            Toggle(isOn: Binding(
                get: { session.previewMode == .grid },
                set: { session.previewMode = $0 ? .grid : .focus }
            )) {
                Label("격자", systemImage: "square.grid.2x2")
            }
            .help("슬라이드를 한눈에 (⌥⌘G)")

            Menu {
                Picker("테마", selection: Binding(
                    get: { session.deck.theme },
                    set: { session.setGlobalDirective("theme", $0) }
                )) {
                    ForEach(ThemeCatalog.all) { theme in
                        Text(theme.label).tag(theme.name)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("테마", systemImage: "paintpalette")
            }
            .help("덱 테마")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                PresenterController.shared.start(session, at: session.activeSlide)
                openWindow(id: PresenterController.windowID)
            } label: {
                Label("발표", systemImage: "play.fill")
            }
            .help("발표 시작 (⌥⌘P)")

            Menu {
                Button("HTML로 내보내기…") { Exporter.exportHTML(session) }
                Button("PDF로 내보내기…") { Exporter.exportPDF(session) }
                Divider()
                Button("프린트…") { Exporter.printDeck(session) }
            } label: {
                Label("내보내기", systemImage: "square.and.arrow.up")
            }
            .help("HTML · PDF 내보내기")

            Button {
                session.inspectorShown.toggle()
            } label: {
                Label("인스펙터", systemImage: "sidebar.trailing")
            }
            .help("인스펙터 (⌥⌘I)")
        }
    }
}
