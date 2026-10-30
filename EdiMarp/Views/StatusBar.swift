import SwiftUI

struct StatusBar: View {
    @ObservedObject var session: DeckSession

    var body: some View {
        HStack(spacing: 14) {
            Text("슬라이드 \(session.activeSlide + 1) / \(session.slideCount)")
            Text("줄 \(session.cursorLine + 1)")
            Text("\(session.deck.wordCount) 단어")
            Spacer()
            if session.isRendering {
                ProgressView().controlSize(.mini)
            }
            Text(ThemeCatalog.label(for: session.deck.theme))
            Text(session.deck.globals["size"] ?? "16:9")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
