import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum OutputFormat: String, CaseIterable, Sendable {
    case json
    case text
    case table

    public static var auto: OutputFormat {
        if let forwardedTTY = ProcessInfo.processInfo.environment["MACKIT_STDOUT_IS_TTY"] {
            return forwardedTTY == "1" ? .text : .json
        }
        return isatty(STDOUT_FILENO) != 0 ? .text : .json
    }
}
