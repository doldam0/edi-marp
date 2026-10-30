import AppKit

/// App-level launch behaviour. Windows are workspace-backed, so there is no
/// untitled-document handling; the app simply stays alive with no windows and
/// each window opens or creates its own workspace.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }
}
