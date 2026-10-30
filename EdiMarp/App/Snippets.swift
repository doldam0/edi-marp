import Foundation

struct Snippet: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let text: String
}

enum Snippets {
    static let all: [Snippet] = [
        Snippet(id: "image", title: "이미지", symbol: "photo", text: "![width:600px](image.png)\n"),
        Snippet(id: "bg", title: "배경 이미지", symbol: "photo.on.rectangle", text: "![bg right:40%](image.png)\n"),
        Snippet(id: "columns", title: "2단 레이아웃", symbol: "rectangle.split.2x1",
                text: "<div style=\"display:grid;grid-template-columns:1fr 1fr;gap:1.5rem\">\n<div>\n\n왼쪽\n\n</div>\n<div>\n\n오른쪽\n\n</div>\n</div>\n"),
        Snippet(id: "code", title: "코드 블록", symbol: "chevron.left.forwardslash.chevron.right", text: "```swift\n\n```\n"),
        Snippet(id: "math", title: "수식", symbol: "x.squareroot", text: "$$\n\n$$\n"),
        Snippet(id: "table", title: "표", symbol: "tablecells", text: "| 항목 | 값 |\n| --- | --- |\n|  |  |\n"),
        Snippet(id: "note", title: "발표자 노트", symbol: "note.text", text: "<!-- 발표자 노트 -->\n"),
    ]
}

enum Templates {
    static func blank(theme: String) -> String {
        "---\nmarp: true\ntheme: \(theme)\npaginate: true\n---\n\n# \n"
    }

    static var welcome: String {
        guard let url = Bundle.main.url(forResource: "Welcome", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return blank(theme: "default") }
        return text
    }
}
