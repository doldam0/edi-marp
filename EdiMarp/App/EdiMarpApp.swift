import SwiftUI

@main
struct EdiMarpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var presenter = PresenterController.shared

    init() {
        Pref.register()
        HeadlessExport.runIfRequested()
    }

    var body: some Scene {
        DocumentGroup(newDocument: { DeckDocument() }) { config in
            DeckWindow(document: config.document, fileURL: config.fileURL)
        }
        .commands { DeckCommands() }
        .defaultSize(width: 1320, height: 840)

        Window("발표", id: PresenterController.windowID) {
            PresenterView()
                .environmentObject(presenter)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1280, height: 720)
        .commandsRemoved()

        Settings {
            SettingsView()
        }
    }
}
