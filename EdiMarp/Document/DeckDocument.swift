import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownDeck = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// The on-disk document: nothing but the markdown text. Undo, autosave,
/// versions and iCloud all come from NSDocument underneath.
final class DeckDocument: ReferenceFileDocument {
    typealias Snapshot = String

    static var readableContentTypes: [UTType] { [.markdownDeck, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownDeck] }

    @Published var text: String

    init(text: String) {
        self.text = text
    }

    /// New document: the welcome deck the very first time, a blank deck after.
    convenience init() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Pref.didShowWelcome) {
            defaults.set(true, forKey: Pref.didShowWelcome)
            self.init(text: Templates.welcome)
        } else {
            self.init(text: Templates.blank(theme: defaults.string(forKey: Pref.defaultTheme) ?? "default"))
        }
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text.replacingOccurrences(of: "\r\n", with: "\n")
    }

    func snapshot(contentType: UTType) throws -> String { text }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}
