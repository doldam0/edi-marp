import SwiftUI

struct DeckToolbar: ToolbarContent {
    @ObservedObject var workspace: Workspace
    @Environment(\.openWindow) private var openWindow

    private var deck: DeckSession { workspace.deck }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                deck.insertSlide()
            } label: {
                Label("새 슬라이드", systemImage: "plus.rectangle.on.rectangle")
            }
            .help("현재 슬라이드 아래에 새 슬라이드 (⌘⏎)")

            Button {
                workspace.importImagesViaPanel()
            } label: {
                Label("이미지 추가", systemImage: "photo.badge.plus")
            }
            .help("이미지를 워크스페이스로 복사하고 덱에 삽입")

            Button {
                deck.insertComment()
            } label: {
                Label("주석 추가", systemImage: "text.bubble")
            }
            .help("발표자 노트 주석(<!-- -->)을 삽입 (⌃⌘/)")

            Picker("레이아웃", selection: Binding(
                get: { deck.layout },
                set: { deck.layout = $0 }
            )) {
                ForEach(DeckSession.Layout.allCases) { layout in
                    Label(layout.title, systemImage: layout.symbol).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .help("편집기 · 분할 · 미리보기 (⌘1 · ⌘2 · ⌘3)")

            Toggle(isOn: Binding(
                get: { deck.previewMode == .grid },
                set: { deck.previewMode = $0 ? .grid : .focus }
            )) {
                Label("격자", systemImage: "square.grid.2x2")
            }
            .help("슬라이드를 한눈에 (⌥⌘G)")

            Menu {
                Picker("테마", selection: Binding(
                    get: { deck.deck.theme },
                    set: { deck.setGlobalDirective("theme", $0) }
                )) {
                    Section("내장") {
                        ForEach(ThemeCatalog.all) { theme in
                            Text(theme.label).tag(theme.name)
                        }
                    }
                    if !workspace.themeFiles.isEmpty {
                        Section("워크스페이스") {
                            ForEach(workspace.themeFiles) { file in
                                Text(file.name).tag(file.name)
                            }
                        }
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
                PresenterController.shared.start(deck, at: deck.activeSlide)
                openWindow(id: PresenterController.windowID)
            } label: {
                Label("발표", systemImage: "play.fill")
            }
            .help("발표 시작 (⌥⌘P)")

            Menu {
                Button("HTML로 내보내기…") { Exporter.exportHTML(deck) }
                Button("PDF로 내보내기…") { Exporter.exportPDF(deck) }
                Divider()
                Button("프린트…") { Exporter.printDeck(deck) }
            } label: {
                Label("내보내기", systemImage: "square.and.arrow.up")
            }
            .help("HTML · PDF 내보내기")

            Button {
                deck.inspectorShown.toggle()
            } label: {
                Label("인스펙터", systemImage: "sidebar.trailing")
            }
            .help("인스펙터 (⌥⌘I)")
        }
    }
}
