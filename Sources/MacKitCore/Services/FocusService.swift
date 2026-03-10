import Foundation

public enum FocusService: Sendable {
    public static func currentStatus() -> FocusStatus {
        // Read DND/Focus status from system defaults
        // The assertionsByProcess key in com.apple.controlcenter indicates active Focus modes
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.controlcenter", "NSStatusItem Visible FocusModes"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // The value is "1" when Focus is enabled in the control center
            let isEnabled = output == "1"
            return FocusStatus(isEnabled: isEnabled, mode: isEnabled ? "Do Not Disturb" : nil)
        } catch {
            return FocusStatus(isEnabled: false, mode: nil)
        }
    }
}
