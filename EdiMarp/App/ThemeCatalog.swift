import Foundation

struct ThemeInfo: Identifiable, Hashable {
    let name: String
    let label: String
    let detail: String
    var id: String { name }
}

enum ThemeCatalog {
    static let all: [ThemeInfo] = [
        ThemeInfo(name: "default", label: "Default", detail: "Marp 기본. 흰 배경, GitHub 느낌"),
        ThemeInfo(name: "gaia", label: "Gaia", detail: "따뜻한 베이지 톤, 큼직한 타이포"),
        ThemeInfo(name: "uncover", label: "Uncover", detail: "미니멀, 넉넉한 여백"),
        ThemeInfo(name: "paper", label: "Paper", detail: "세리프, 종이 질감의 에디토리얼"),
        ThemeInfo(name: "noir", label: "Noir", detail: "블랙 + 라임 악센트, 개발자 발표용"),
    ]

    static func label(for name: String) -> String {
        all.first { $0.name == name }?.label ?? name
    }
}
