import SwiftUI

struct PreviewView: View {
    @ObservedObject var session: DeckSession

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if session.previewMode == .grid {
                GridPreview(session: session)
            } else {
                FocusPreview(session: session)
            }
            if let error = session.renderError {
                VStack {
                    Spacer()
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }
        }
    }
}

/// One slide, fit to the panel. Click any block to jump the editor to its line.
private struct FocusPreview: View {
    @ObservedObject var session: DeckSession

    var body: some View {
        VStack(spacing: 0) {
            SlideCard(session: session, index: session.activeSlide, interactive: true, passthrough: false,
                      onLine: { session.goToLine($0) })
                .padding(28)
            HStack(spacing: 16) {
                Button { session.previousSlide() } label: { Image(systemName: "chevron.left") }
                    .disabled(session.activeSlide == 0)
                Text("\(session.activeSlide + 1) / \(session.slideCount)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 56)
                Button { session.nextSlide() } label: { Image(systemName: "chevron.right") }
                    .disabled(session.activeSlide >= session.slideCount - 1)
            }
            .buttonStyle(.borderless)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Every slide at once. Click selects, double-click opens it in focus view.
private struct GridPreview: View {
    @ObservedObject var session: DeckSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 420), spacing: 18)], spacing: 18) {
                    ForEach(session.deck.slides) { slide in
                        VStack(spacing: 6) {
                            SlideCard(session: session, index: slide.index, cornerRadius: 5, shadow: 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(slide.index == session.activeSlide ? Color.accentColor : Color.primary.opacity(0.1),
                                                      lineWidth: slide.index == session.activeSlide ? 2.5 : 0.5)
                                )
                            Text("\(slide.index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .id(slide.index)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            session.selectSlide(slide.index)
                            session.previewMode = .focus
                        }
                        .onTapGesture { session.selectSlide(slide.index) }
                    }
                }
                .padding(24)
            }
            .onChange(of: session.activeSlide) { _, index in
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }
}
