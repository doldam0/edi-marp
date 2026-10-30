import Foundation

/// A single text replacement, expressed in UTF-16 offsets so it maps 1:1 onto
/// `NSTextView` / `NSTextStorage` ranges. Every GUI operation in the app is
/// reduced to an array of these; the editor applies them as one undoable step.
public struct Edit: Equatable, Sendable {
    public var range: NSRange
    public var insert: String

    public init(range: NSRange, insert: String) {
        self.range = range
        self.insert = insert
    }

    public init(at offset: Int, insert: String) {
        self.init(range: NSRange(location: offset, length: 0), insert: insert)
    }

    public static func delete(_ range: NSRange) -> Edit {
        Edit(range: range, insert: "")
    }
}

public extension Array where Element == Edit {
    /// Applies the edits to `source`. Edits must not overlap; they are applied
    /// back-to-front so earlier offsets stay valid.
    func apply(to source: String) -> String {
        let text = NSMutableString(string: source)
        for edit in sorted(by: { $0.range.location > $1.range.location }) {
            text.replaceCharacters(in: edit.range, with: edit.insert)
        }
        return text as String
    }
}
