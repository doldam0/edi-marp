import SwiftUI

/// Runs once per launch so only the first window auto-opens a workspace;
/// later ⌘N windows show the welcome screen.
enum LaunchState { static var autoOpened = false }

@main
struct EdiMarpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var presenter = PresenterController.shared

    init() {
        Pref.register()
        HeadlessExport.runIfRequested()
    }

    var body: some Scene {
        WindowGroup(for: WorkspaceRef.self) { $ref in
            WorkspaceWindow(ref: $ref)
                .onAppear {
                    if ref == nil, !LaunchState.autoOpened {
                        LaunchState.autoOpened = true
                        ref = EdiMarpApp.launchRef()
                    }
                }
        }
        .commands { DeckCommands() }
        .defaultSize(width: 1360, height: 860)

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

    /// The workspace to open on the first window: a test folder when driving
    /// the smoke test, otherwise the most recent workspace.
    private static func launchRef() -> WorkspaceRef? {
        if let path = ProcessInfo.processInfo.environment["EDIMARP_TEST_WORKSPACE"] {
            return try? WorkspaceRef.make(for: URL(fileURLWithPath: path))
        }
        return RecentWorkspaces.mostRecent
    }
}
