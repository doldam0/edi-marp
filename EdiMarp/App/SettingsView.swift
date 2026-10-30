import SwiftUI

struct SettingsView: View {
    @AppStorage(Pref.editorFontSize) private var fontSize = 13.0
    @AppStorage(Pref.showGutter) private var showGutter = true
    @AppStorage(Pref.defaultTheme) private var defaultTheme = "default"

    var body: some View {
        Form {
            Section("편집기") {
                Slider(value: $fontSize, in: 10...24, step: 1) {
                    Text("글자 크기")
                } minimumValueLabel: {
                    Text("10").font(.caption)
                } maximumValueLabel: {
                    Text("24").font(.caption)
                }
                Toggle("줄 번호와 슬라이드 배지", isOn: $showGutter)
            }
            Section("새 문서") {
                Picker("기본 테마", selection: $defaultTheme) {
                    ForEach(ThemeCatalog.all) { theme in
                        Text(theme.label).tag(theme.name)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
