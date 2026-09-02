import Foundation
import os

/// Unified logging plus stderr echo when NOTCHUSAGE_DEBUG=1 (handy when run from a terminal).
enum Log {
    static let logger = Logger(subsystem: "io.github.minsueh.NotchUsage", category: "usage")
    static let debug = ProcessInfo.processInfo.environment["NOTCHUSAGE_DEBUG"] == "1"

    static func info(_ msg: String) {
        logger.info("\(msg, privacy: .public)")
        if debug { FileHandle.standardError.write(Data("[NotchUsage] \(msg)\n".utf8)) }
    }
    static func error(_ msg: String) {
        logger.error("\(msg, privacy: .public)")
        if debug { FileHandle.standardError.write(Data("[NotchUsage] ERROR \(msg)\n".utf8)) }
    }
}
