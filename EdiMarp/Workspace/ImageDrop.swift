import SwiftUI
import UniformTypeIdentifiers

/// Shared drag-and-drop handling for images: a file dragged from Finder is
/// copied into the workspace, image data dragged from another app is written
/// to the assets folder, and either way an image tag is inserted into the deck.
enum ImageDrop {
    /// Accept file URLs (Finder) and raw image data (other apps).
    static let types: [UTType] = [.fileURL, .image]

    @MainActor
    static func handle(_ providers: [NSItemProvider], into workspace: Workspace) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    Task { @MainActor in workspace.insertImage(from: url) }
                }
            } else if let type = imageType(of: provider) {
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    guard let data else { return }
                    let ext = type.preferredFilenameExtension ?? "png"
                    Task { @MainActor in workspace.insertImage(data: data, fileExtension: ext) }
                }
            }
        }
        return handled
    }

    private static func imageType(of provider: NSItemProvider) -> UTType? {
        provider.registeredTypeIdentifiers
            .compactMap(UTType.init)
            .first { $0.conforms(to: .image) }
    }
}

extension View {
    /// Accepts dropped images, importing them into the workspace's deck.
    func imageDropTarget(_ workspace: Workspace) -> some View {
        modifier(ImageDropModifier(workspace: workspace))
    }
}

private struct ImageDropModifier: ViewModifier {
    let workspace: Workspace
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: ImageDrop.types, isTargeted: $targeted) { ImageDrop.handle($0, into: workspace) }
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .background(Color.accentColor.opacity(0.06))
                        .padding(3)
                        .allowsHitTesting(false)
                }
            }
    }
}
