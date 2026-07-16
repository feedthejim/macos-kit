import ArgumentParser
import Foundation
import MacKitCore

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check the MacKit installation and local host"
    )

    @OptionGroup var globals: GlobalOptions

    func run() throws {
        let checks = HostClient.diagnostics()
        if globals.effectiveFormat == .json {
            let values = checks.map { check in
                [
                    "name": check.name,
                    "status": check.passed ? "ok" : "failed",
                    "detail": check.detail,
                ]
            }
            print(try OutputRenderer.renderJSON(values))
        } else {
            for check in checks {
                print("\(check.passed ? "OK" : "FAIL")  \(check.name): \(check.detail)")
            }
        }
        if checks.contains(where: { !$0.passed }) {
            throw ExitCode.failure
        }
    }
}
