import SwiftUI
import EdiCore

/// Native inspector. Every control writes a directive into the markdown
/// through a transform; nothing here holds its own state.
struct InspectorView: View {
    @ObservedObject var session: DeckSession

    var body: some View {
        Form {
            if let slide = session.activeSlideModel {
                Section("슬라이드 \(slide.index + 1)") {
                    Toggle("리드 (lead)", isOn: classBinding("lead", slide))
                    Toggle("반전 (invert)", isOn: classBinding("invert", slide))
                    Toggle("페이지 번호", isOn: paginateBinding(slide))
                    DirectiveColorRow(session: session, slide: slide, key: "backgroundColor", title: "배경색", fallback: .white)
                    DirectiveColorRow(session: session, slide: slide, key: "color", title: "글자색", fallback: .black)
                }
                let others = slide.declared.filter { !["class", "paginate", "backgroundColor", "color"].contains($0.key) }
                if !others.isEmpty {
                    Section("이 슬라이드의 디렉티브") {
                        ForEach(Array(others.enumerated()), id: \.offset) { _, directive in
                            HStack {
                                Text((directive.isSpot ? "_" : "") + directive.key)
                                    .font(.callout.monospaced())
                                Spacer()
                                Text(directive.value)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { session.goToLine(directive.line) }
                        }
                    }
                }
            }

            Section("덱") {
                Picker("테마", selection: Binding(
                    get: { session.deck.theme },
                    set: { session.setGlobalDirective("theme", $0) }
                )) {
                    ForEach(ThemeCatalog.all) { theme in
                        Text(theme.label).tag(theme.name)
                    }
                }
                Picker("비율", selection: Binding(
                    get: { session.deck.globals["size"] ?? "16:9" },
                    set: { session.setGlobalDirective("size", $0 == "16:9" ? nil : $0) }
                )) {
                    Text("16:9").tag("16:9")
                    Text("4:3").tag("4:3")
                }
                Toggle("페이지 번호", isOn: Binding(
                    get: { session.deck.frontmatterValues["paginate"] == "true" },
                    set: { session.setGlobalDirective("paginate", $0 ? "true" : nil) }
                ))
                DirectiveTextRow(session: session, key: "header", title: "머리글")
                DirectiveTextRow(session: session, key: "footer", title: "바닥글")
            }

            if let theme = ThemeCatalog.all.first(where: { $0.name == session.deck.theme }) {
                Section {
                    Text(theme.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func classBinding(_ name: String, _ slide: Slide) -> Binding<Bool> {
        Binding(
            get: { slide.classes.contains(name) },
            set: { _ in session.toggleClass(name) }
        )
    }

    private func paginateBinding(_ slide: Slide) -> Binding<Bool> {
        Binding(
            get: { slide.effective["paginate"] == "true" },
            set: { on in
                let deckDefault = session.deck.frontmatterValues["paginate"] == "true"
                session.setSlideDirective("paginate", on == deckDefault ? nil : (on ? "true" : "false"))
            }
        )
    }
}

/// Color picker bound to a spot directive, with the writes coalesced so a
/// drag in the color panel is one undo step instead of hundreds.
private struct DirectiveColorRow: View {
    @ObservedObject var session: DeckSession
    let slide: Slide
    let key: String
    let title: String
    let fallback: Color
    @State private var pending: Task<Void, Never>?

    private var current: String? { slide.declared(key, spot: true)?.value ?? slide.effective[key] }

    var body: some View {
        HStack {
            ColorPicker(title, selection: Binding(
                get: { current.flatMap(Color.init(hex:)) ?? fallback },
                set: { color in
                    guard let hex = color.hexString else { return }
                    pending?.cancel()
                    pending = Task {
                        try? await Task.sleep(for: .milliseconds(120))
                        guard !Task.isCancelled else { return }
                        session.setSlideDirective(key, hex)
                    }
                }
            ), supportsOpacity: false)
            if slide.declared(key, spot: true) != nil {
                Button {
                    session.setSlideDirective(key, nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .help("\(title) 제거")
            }
        }
    }
}

/// Text field bound to a front matter value; commits on return or focus loss.
private struct DirectiveTextRow: View {
    @ObservedObject var session: DeckSession
    let key: String
    let title: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text, prompt: Text("없음"))
            .focused($focused)
            .onAppear { text = session.deck.frontmatterValues[key] ?? "" }
            .onChange(of: session.deck.frontmatterValues[key]) { _, value in
                if !focused { text = value ?? "" }
            }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onSubmit(commit)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let current = session.deck.frontmatterValues[key] ?? ""
        guard trimmed != current else { return }
        session.setGlobalDirective(key, trimmed.isEmpty ? nil : "\"\(trimmed)\"")
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var hexString: String? {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(rgb.redComponent * 255)), g = Int(round(rgb.greenComponent * 255)), b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
