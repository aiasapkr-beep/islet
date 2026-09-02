import Foundation
import os

/// Unified logging plus stderr echo when ISLET_DEBUG=1 (handy when run from a terminal).
enum Log {
    static let logger = Logger(subsystem: "kr.asapai.Islet", category: "usage")
    static let debug = ProcessInfo.processInfo.environment["ISLET_DEBUG"] == "1"

    static func info(_ msg: String) {
        logger.info("\(msg, privacy: .public)")
        if debug { FileHandle.standardError.write(Data("[Islet] \(msg)\n".utf8)) }
    }
    static func error(_ msg: String) {
        logger.error("\(msg, privacy: .public)")
        if debug { FileHandle.standardError.write(Data("[Islet] ERROR \(msg)\n".utf8)) }
    }
}
