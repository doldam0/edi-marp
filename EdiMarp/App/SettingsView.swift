import SwiftUI
import UniformTypeIdentifiers

/// Bridges SwiftUI to the system font panel so the editor font can be chosen
/// directly, with live family/typeface/size, instead of from a fixed list.
@MainActor
final class FontPanelController: NSObject {
    static let shared = FontPanelController()

    private var current: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    private var onChange: ((NSFont) -> Void)?

    func present(current: NSFont, onChange: @escaping (NSFont) -> Void) {
        self.current = current
        self.onChange = onChange
        let manager = NSFontManager.shared
        manager.target = self
        manager.action = #selector(changeFont(_:))
        manager.setSelectedFont(current, isMultiple: false)
        manager.orderFrontFontPanel(self)
    }

    @objc func changeFont(_ sender: NSFontManager?) {
        guard let sender else { return }
        let newFont = sender.convert(current)
        current = newFont
        onChange?(newFont)
    }

    /// Hide the color/effects controls; only family, typeface, and size matter.
    @objc func validModesForFontPanel(_ panel: NSFontPanel) -> NSFontPanel.ModeMask {
        [.collection, .face, .size]
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            EditorSettings()
                .tabItem { Label("편집기", systemImage: "textformat") }
            DocumentSettings()
                .tabItem { Label("문서", systemImage: "doc.text") }
            ExportSettings()
                .tabItem { Label("내보내기", systemImage: "square.and.arrow.up") }
        }
        .frame(width: 460)
    }
}

private struct EditorSettings: View {
    @AppStorage(Pref.editorFontSize) private var fontSize = 13.0
    @AppStorage(Pref.editorFontName) private var fontName = ""
    @AppStorage(Pref.showGutter) private var showGutter = true
    @AppStorage(Pref.spellCheck) private var spellCheck = true

    private var currentFont: NSFont {
        (fontName.isEmpty ? nil : NSFont(name: fontName, size: fontSize))
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private var fontLabel: String {
        fontName.isEmpty ? "시스템 고정폭" : (currentFont.displayName ?? fontName)
    }

    var body: some View {
        Form {
            Section("글꼴") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fontLabel).font(.custom(currentFont.fontName, size: 13))
                        Text("\(Int(fontSize)) pt").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !fontName.isEmpty {
                        Button("기본값") { fontName = "" }
                    }
                    Button("글꼴 선택…") {
                        FontPanelController.shared.present(current: currentFont) { font in
                            fontName = font.fontName
                            fontSize = min(24, max(10, Double(font.pointSize)))
                        }
                    }
                }
                HStack {
                    Slider(value: $fontSize, in: 10...24, step: 1)
                    Stepper(value: $fontSize, in: 10...24, step: 1) {
                        Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                Text("편집기 글꼴과 크기. 미리보기는 테마가 정합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("표시") {
                Toggle("줄 번호와 슬라이드 배지", isOn: $showGutter)
                Toggle("맞춤법 검사", isOn: $spellCheck)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

private struct DocumentSettings: View {
    @AppStorage(Pref.defaultTheme) private var defaultTheme = "default"

    var body: some View {
        Form {
            Section("새 문서") {
                Picker("기본 테마", selection: $defaultTheme) {
                    ForEach(ThemeCatalog.all) { theme in
                        Text(theme.label).tag(theme.name)
                    }
                }
                Text("새 워크스페이스의 시작 덱에 쓰이는 테마입니다. 워크스페이스에 둔 `/* @theme */` CSS는 자동으로 인식됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

private struct ExportSettings: View {
    @AppStorage(Pref.marpPath) private var marpPath = ""
    @AppStorage(Pref.chromePath) private var chromePath = ""

    private var marp: URL? { MarpCLI.findMarp() }
    private var chrome: URL? { MarpCLI.findChrome() }

    var body: some View {
        Form {
            Section("PDF · 프린트") {
                status(label: "marp-cli", url: marp,
                       missing: "설치 필요: npm i -g @marp-team/marp-cli")
                status(label: "Chrome", url: chrome,
                       missing: "Google Chrome가 필요합니다")
                Text("PDF와 프린트는 marp-cli가 헤드리스 Chrome으로 렌더합니다. 미리보기와 HTML 내보내기에는 필요 없습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("경로 직접 지정 (선택)") {
                pathRow(title: "marp 실행 파일", binding: $marpPath, chooseDirectories: false)
                pathRow(title: "Chrome", binding: $chromePath, chooseDirectories: false)
                Text("비워 두면 자동으로 찾습니다. 앱에 marp-cli를 동봉하면 설치 없이 동작합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private func status(label: String, url: URL?, missing: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: url != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(url != nil ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                Text(url?.path ?? missing)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
    }

    private func pathRow(title: String, binding: Binding<String>, chooseDirectories: Bool) -> some View {
        HStack {
            TextField(title, text: binding, prompt: Text("자동"))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("찾아보기…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = chooseDirectories
                panel.allowsMultipleSelection = false
                panel.treatsFilePackagesAsDirectories = true
                if panel.runModal() == .OK, let path = panel.url?.path {
                    binding.wrappedValue = path
                }
            }
            if !binding.wrappedValue.isEmpty {
                Button("지우기") { binding.wrappedValue = "" }
            }
        }
    }
}
