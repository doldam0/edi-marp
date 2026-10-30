import AppKit

/// Launch behaviour: a fresh launch with nothing to restore opens an untitled
/// deck (the welcome deck the first time) instead of the Open panel.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSDocumentController.shared.newDocument(nil) }
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Diag.enabled || ProcessInfo.processInfo.environment["EDIMARP_EXPORT_INPUT"] == nil else { return }
        DispatchQueue.main.async {
            if NSDocumentController.shared.documents.isEmpty, NSApp.windows.allSatisfy({ !$0.isVisible || $0 is NSPanel }) {
                NSDocumentController.shared.newDocument(nil)
            }
        }
    }
}
