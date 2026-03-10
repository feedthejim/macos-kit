import ArgumentParser
import MacKitCore

struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Output format: json, text, or table")
    var format: String?

    @Flag(name: .long, help: "Disable colored output")
    var noColor: Bool = false

    var effectiveFormat: OutputFormat {
        if let format, let parsed = OutputFormat(rawValue: format) {
            return parsed
        }
        return .auto
    }
}
