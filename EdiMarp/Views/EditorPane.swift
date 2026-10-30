import SwiftUI

/// The editor panel: a thin bar with the `</>` (deck markdown) and brush
/// (theme CSS) shortcuts and the current file's name, over the editor for the
/// current file. Selecting a file in the explorer or pressing a shortcut swaps
/// what is shown here; the preview always tracks the active deck.
struct EditorPane: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 6) {
            shortcut(symbol: "chevron.left.forwardslash.chevron.right", active: workspace.isShowingDeck,
                     help: "덱 마크다운") { workspace.showDeckFile() }
            shortcut(symbol: "paintbrush", active: workspace.isShowingTheme,
                     help: "테마 CSS 편집") { workspace.showThemeFile() }

            Divider().frame(height: 14)

            Text(currentName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if workspace.currentIsMarkdown, workspace.deck.isDirty {
                Circle().fill(Color.secondary).frame(width: 5, height: 5)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.bar)
    }

    private func shortcut(symbol: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 20)
                .background(active ? Color.accentColor.opacity(0.18) : .clear,
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.accentColor : .secondary)
        .help(help)
    }

    @ViewBuilder private var content: some View {
        if workspace.showThemePrompt {
            ThemePromptView(workspace: workspace)
        } else if let editor = workspace.currentEditor {
            EditorView(controller: editor)
                .id(workspace.currentFileURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("열 수 없는 파일", systemImage: "doc",
                                   description: Text("텍스트 파일만 편집기에서 열 수 있습니다."))
        }
    }

    private var currentName: String {
        workspace.showThemePrompt ? "새 테마" : workspace.currentFileURL.lastPathComponent
    }
}

/// Shown when the brush is pressed while the deck uses a built-in theme, which
/// cannot be edited directly.
private struct ThemePromptView: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "paintbrush.pointed")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text(.init("현재 내장 테마 **\(workspace.deck.deck.theme)** 를 사용 중입니다."))
                .font(.title3)
            Text("내장 테마는 직접 편집할 수 없습니다.\n커스텀 테마를 만들고 편집하시겠습니까?")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                workspace.createCustomTheme()
            } label: {
                Label("커스텀 테마 만들기", systemImage: "plus")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("취소") {
                workspace.showThemePrompt = false
                workspace.showDeckFile()
            }
            .buttonStyle(.link)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
