import Foundation

/// UserDefaults keys shared by Settings and the sessions.
enum Pref {
    static let editorFontSize = "editorFontSize"
    static let defaultTheme = "defaultTheme"
    static let showGutter = "showGutter"
    static let layout = "layout"
    static let previewMode = "previewMode"
    static let inspector = "inspectorShown"
    static let didShowWelcome = "didShowWelcome"

    static func register() {
        UserDefaults.standard.register(defaults: [
            editorFontSize: 13.0,
            defaultTheme: "default",
            showGutter: true,
            layout: "split",
            previewMode: "focus",
            inspector: false,
        ])
    }
}
