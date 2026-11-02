import Foundation

/// UserDefaults keys shared by Settings and the sessions.
enum Pref {
    static let editorFontSize = "editorFontSize"
    static let editorFontName = "editorFontName"
    static let defaultTheme = "defaultTheme"
    static let showGutter = "showGutter"
    static let spellCheck = "spellCheck"
    static let layout = "layout"
    static let previewMode = "previewMode"
    static let inspector = "inspectorShown"
    static let sidebarMode = "sidebarMode"
    static let didShowWelcome = "didShowWelcome"
    /// Optional overrides for PDF export; empty means auto-detect.
    static let marpPath = "marpPath"
    static let chromePath = "chromePath"

    static func register() {
        UserDefaults.standard.register(defaults: [
            editorFontSize: 13.0,
            editorFontName: "",
            defaultTheme: "default",
            showGutter: true,
            spellCheck: true,
            layout: "split",
            previewMode: "focus",
            inspector: false,
            sidebarMode: "slides",
            marpPath: "",
            chromePath: "",
        ])
    }
}
