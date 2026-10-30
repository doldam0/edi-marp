import SwiftUI

/// Thumbnails in a native sidebar list: click to jump, drag to reorder,
/// right-click for slide actions. Reordering is just another text edit.
struct SlideSidebar: View {
    @ObservedObject var session: DeckSession

    private var selection: Binding<Int?> {
        Binding(
            get: { session.activeSlide },
            // Only act on a genuine change. SwiftUI re-emits the current value on
            // every render pass; treating that as a selection would move the caret
            // in a loop with caret-tracking.
            set: { if let index = $0, index != session.activeSlide { session.selectSlide(index) } }
        )
    }

    var body: some View {
        List(selection: selection) {
            ForEach(session.deck.slides) { slide in
                SlideRow(session: session, index: slide.index, title: slide.title)
                    .tag(slide.index)
                    .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
            }
            .onMove { from, to in
                guard let source = from.first else { return }
                let target = to > source ? to - 1 : to
                session.moveSlide(from: source, to: target)
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: Int.self) { items in
            if let index = items.first {
                Button("아래에 새 슬라이드") { session.selectSlide(index); session.insertSlide() }
                Button("복제") { session.selectSlide(index); session.duplicateSlide() }
                Divider()
                Button("삭제", role: .destructive) { session.deleteSlide(index) }
            }
        } primaryAction: { items in
            if let index = items.first { session.selectSlide(index, focusEditor: true) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button {
                    session.insertSlide()
                } label: {
                    Label("새 슬라이드", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

private struct SlideRow: View {
    @ObservedObject var session: DeckSession
    let index: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SlideCard(session: session, index: index, cornerRadius: 4, shadow: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
            HStack(spacing: 6) {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                Text(title.isEmpty ? "빈 슬라이드" : title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(title.isEmpty ? .tertiary : .secondary)
            }
            .padding(.horizontal, 2)
        }
    }
}
