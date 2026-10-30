import Foundation
import os

/// Opt-in diagnostics. `EDIMARP_DEBUG=1` logs the data flow to the unified
/// log; `EDIMARP_DEBUG=/path/to/file` appends it to that file instead.
enum Diag {
    private static let target = ProcessInfo.processInfo.environment["EDIMARP_DEBUG"]
    static var enabled: Bool { target != nil }
    private static let logger = Logger(subsystem: "com.doldam0.EdiMarp", category: "diag")
    private static let start = Date()

    static func log(_ message: @autoclosure () -> String) {
        guard let target else { return }
        let text = message()
        if target.hasPrefix("/") {
            let line = String(format: "%8.3f  %@\n", Date().timeIntervalSince(start), text)
            if let handle = FileHandle(forWritingAtPath: target) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                handle.closeFile()
            } else {
                FileManager.default.createFile(atPath: target, contents: Data(line.utf8))
            }
        } else {
            logger.notice("\(text, privacy: .public)")
        }
    }
}
