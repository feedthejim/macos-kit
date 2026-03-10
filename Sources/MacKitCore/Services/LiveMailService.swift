import Foundation
import ScriptingBridge

public final class LiveMailService: MailServiceProtocol, @unchecked Sendable {
    private let app: SBApplication?

    public init() {
        self.app = SBApplication(bundleIdentifier: "com.apple.mail")
    }

    public func ensureRunning() async throws {
        guard let app else {
            throw MacKitError.appNotRunning("Mail.app")
        }
        if !app.isRunning {
            app.activate()
            // Give Mail.app a moment to launch
            try await Task.sleep(nanoseconds: 2_000_000_000)
            if !app.isRunning {
                throw MacKitError.appNotRunning("Mail.app")
            }
        }
    }

    private var mailApp: SBApplication {
        get throws {
            guard let app else {
                throw MacKitError.appNotRunning("Mail.app")
            }
            return app
        }
    }

    // MARK: - Read Operations

    public func accounts() async throws -> [MailAccount] {
        try await ensureRunning()
        guard let sbAccounts = try mailApp.value(forKey: "accounts") as? SBElementArray else {
            return []
        }
        return sbAccounts.compactMap { element -> MailAccount? in
            guard let obj = element as? SBObject else { return nil }
            let name = obj.value(forKey: "name") as? String ?? "Unknown"
            let emails = obj.value(forKey: "emailAddresses") as? [String] ?? []
            return MailAccount(name: name, emailAddresses: emails)
        }
    }

    public func mailboxes(account: String?) async throws -> [Mailbox] {
        try await ensureRunning()
        guard let sbAccounts = try mailApp.value(forKey: "accounts") as? SBElementArray else {
            return []
        }
        var result: [Mailbox] = []
        for element in sbAccounts {
            guard let acct = element as? SBObject else { continue }
            let acctName = acct.value(forKey: "name") as? String ?? "Unknown"
            if let account, acctName != account { continue }
            guard let sbMailboxes = acct.value(forKey: "mailboxes") as? SBElementArray else { continue }
            for mbElement in sbMailboxes {
                guard let mb = mbElement as? SBObject else { continue }
                let mbName = mb.value(forKey: "name") as? String ?? "?"
                let unread = mb.value(forKey: "unreadCount") as? Int ?? 0
                let count = (mb.value(forKey: "messages") as? SBElementArray)?.count ?? 0
                result.append(Mailbox(name: mbName, account: acctName, unreadCount: unread, messageCount: count))
            }
        }
        return result
    }

    public func messages(mailbox: String?, account: String?, limit: Int, unreadOnly: Bool) async throws -> [MailMessage] {
        try await ensureRunning()
        let targetMailbox = mailbox ?? "INBOX"
        guard let sbMailbox = findMailbox(named: targetMailbox, account: account) else {
            throw MacKitError.notFound("Mailbox '\(targetMailbox)'" + (account.map { " in account '\($0)'" } ?? ""))
        }
        let acctName = account ?? accountName(for: sbMailbox)
        guard let sbMessages = sbMailbox.value(forKey: "messages") as? SBElementArray else {
            return []
        }

        var result: [MailMessage] = []
        let total = sbMessages.count
        for i in 0..<min(total, limit * 2) {
            guard let msg = sbMessages.object(at: i) as? SBObject else { continue }
            let isRead = msg.value(forKey: "readStatus") as? Bool ?? false
            if unreadOnly && isRead { continue }

            result.append(mapMessage(msg, mailbox: targetMailbox, account: acctName))
            if result.count >= limit { break }
        }
        return result
    }

    public func searchMessages(query: String, mailbox: String?, account: String?, limit: Int) async throws -> [MailMessage] {
        try await ensureRunning()
        let lowerQuery = query.lowercased()
        var result: [MailMessage] = []

        let mailboxesToSearch: [(SBObject, String, String)] = findMailboxes(named: mailbox, account: account)

        for (sbMailbox, mbName, acctName) in mailboxesToSearch {
            guard let sbMessages = sbMailbox.value(forKey: "messages") as? SBElementArray else { continue }
            let total = sbMessages.count
            for i in 0..<min(total, 100) {
                guard let msg = sbMessages.object(at: i) as? SBObject else { continue }
                let subject = (msg.value(forKey: "subject") as? String ?? "").lowercased()
                let sender = (msg.value(forKey: "sender") as? String ?? "").lowercased()
                if subject.contains(lowerQuery) || sender.contains(lowerQuery) {
                    result.append(mapMessage(msg, mailbox: mbName, account: acctName))
                    if result.count >= limit { return result }
                }
            }
        }
        return result
    }

    public func getMessage(id: String, mailbox: String, account: String) async throws -> MailMessage {
        try await ensureRunning()
        guard let sbMailbox = findMailbox(named: mailbox, account: account) else {
            throw MacKitError.notFound("Mailbox '\(mailbox)' in account '\(account)'")
        }
        guard let sbMessages = sbMailbox.value(forKey: "messages") as? SBElementArray else {
            throw MacKitError.notFound("Message \(id)")
        }

        let total = sbMessages.count
        for i in 0..<total {
            guard let msg = sbMessages.object(at: i) as? SBObject else { continue }
            let msgId = "\(msg.value(forKey: "id") ?? "")"
            if msgId == id {
                return mapMessage(msg, mailbox: mailbox, account: account, includeContent: true)
            }
        }
        throw MacKitError.notFound("Message \(id)")
    }

    // MARK: - Write Operations

    public func sendMessage(to: [String], cc: [String], bcc: [String], subject: String, body: String, from: String?) async throws {
        try await ensureRunning()
        // Build AppleScript for sending since ScriptingBridge's KVC approach is unreliable for creating new messages
        var script = "tell application \"Mail\"\n"
        script += "  set newMessage to make new outgoing message with properties {subject:\"\(escapeAS(subject))\", content:\"\(escapeAS(body))\", visible:false}\n"
        script += "  tell newMessage\n"
        for addr in to {
            script += "    make new to recipient at end of to recipients with properties {address:\"\(escapeAS(addr))\"}\n"
        }
        for addr in cc {
            script += "    make new cc recipient at end of cc recipients with properties {address:\"\(escapeAS(addr))\"}\n"
        }
        for addr in bcc {
            script += "    make new bcc recipient at end of bcc recipients with properties {address:\"\(escapeAS(addr))\"}\n"
        }
        if let from {
            script += "    set sender to \"\(escapeAS(from))\"\n"
        }
        script += "  end tell\n"
        script += "  send newMessage\n"
        script += "end tell\n"
        try runAppleScript(script)
    }

    public func markRead(id: String, mailbox: String, account: String) async throws {
        try await ensureRunning()
        let msg = try findSBMessage(id: id, mailbox: mailbox, account: account)
        msg.setValue(true, forKey: "readStatus")
    }

    public func markUnread(id: String, mailbox: String, account: String) async throws {
        try await ensureRunning()
        let msg = try findSBMessage(id: id, mailbox: mailbox, account: account)
        msg.setValue(false, forKey: "readStatus")
    }

    public func moveMessage(id: String, fromMailbox: String, toMailbox: String, account: String) async throws {
        try await ensureRunning()
        // Use AppleScript for move since KVC can't express the "move to" target
        let script = """
            tell application "Mail"
                set targetMailbox to mailbox "\(escapeAS(toMailbox))" of account "\(escapeAS(account))"
                set targetAccount to account "\(escapeAS(account))"
                set msgs to messages of mailbox "\(escapeAS(fromMailbox))" of targetAccount
                repeat with m in msgs
                    if (id of m as text) is "\(escapeAS(id))" then
                        move m to targetMailbox
                        return "ok"
                    end if
                end repeat
                error "Message not found"
            end tell
            """
        try runAppleScript(script)
    }

    public func deleteMessage(id: String, mailbox: String, account: String) async throws {
        try await ensureRunning()
        let script = """
            tell application "Mail"
                set targetAccount to account "\(escapeAS(account))"
                set msgs to messages of mailbox "\(escapeAS(mailbox))" of targetAccount
                repeat with m in msgs
                    if (id of m as text) is "\(escapeAS(id))" then
                        delete m
                        return "ok"
                    end if
                end repeat
                error "Message not found"
            end tell
            """
        try runAppleScript(script)
    }

    // MARK: - Helpers

    private func findMailbox(named name: String, account: String?) -> SBObject? {
        guard let sbAccounts = app?.value(forKey: "accounts") as? SBElementArray else { return nil }
        for element in sbAccounts {
            guard let acct = element as? SBObject else { continue }
            let acctName = acct.value(forKey: "name") as? String ?? ""
            if let account, acctName != account { continue }
            guard let sbMailboxes = acct.value(forKey: "mailboxes") as? SBElementArray else { continue }
            for mbElement in sbMailboxes {
                guard let mb = mbElement as? SBObject else { continue }
                if (mb.value(forKey: "name") as? String) == name {
                    return mb
                }
            }
        }
        return nil
    }

    private func findMailboxes(named name: String?, account: String?) -> [(SBObject, String, String)] {
        guard let sbAccounts = app?.value(forKey: "accounts") as? SBElementArray else { return [] }
        var result: [(SBObject, String, String)] = []
        for element in sbAccounts {
            guard let acct = element as? SBObject else { continue }
            let acctName = acct.value(forKey: "name") as? String ?? ""
            if let account, acctName != account { continue }
            guard let sbMailboxes = acct.value(forKey: "mailboxes") as? SBElementArray else { continue }
            for mbElement in sbMailboxes {
                guard let mb = mbElement as? SBObject else { continue }
                let mbName = mb.value(forKey: "name") as? String ?? ""
                if let name {
                    if mbName == name { result.append((mb, mbName, acctName)) }
                } else {
                    if mbName == "INBOX" { result.append((mb, mbName, acctName)) }
                }
            }
        }
        return result
    }

    private func findSBMessage(id: String, mailbox: String, account: String) throws -> SBObject {
        guard let sbMailbox = findMailbox(named: mailbox, account: account) else {
            throw MacKitError.notFound("Mailbox '\(mailbox)' in account '\(account)'")
        }
        guard let sbMessages = sbMailbox.value(forKey: "messages") as? SBElementArray else {
            throw MacKitError.notFound("Message \(id)")
        }
        let total = sbMessages.count
        for i in 0..<total {
            guard let msg = sbMessages.object(at: i) as? SBObject else { continue }
            if "\(msg.value(forKey: "id") ?? "")" == id {
                return msg
            }
        }
        throw MacKitError.notFound("Message \(id)")
    }

    private func accountName(for mailbox: SBObject) -> String {
        // Walk up to find account name
        if let acct = mailbox.value(forKey: "account") as? SBObject {
            return acct.value(forKey: "name") as? String ?? ""
        }
        return ""
    }

    private func mapMessage(_ msg: SBObject, mailbox: String, account: String, includeContent: Bool = false) -> MailMessage {
        let id = "\(msg.value(forKey: "id") ?? "")"
        let subject = msg.value(forKey: "subject") as? String ?? ""
        let sender = msg.value(forKey: "sender") as? String ?? ""
        let dateSent = msg.value(forKey: "dateSent") as? Date
        let dateReceived = msg.value(forKey: "dateReceived") as? Date ?? Date()
        let isRead = msg.value(forKey: "readStatus") as? Bool ?? false

        var toRecipients: [String] = []
        if let toArray = msg.value(forKey: "toRecipients") as? SBElementArray {
            for r in toArray {
                if let recipient = r as? SBObject,
                   let addr = recipient.value(forKey: "address") as? String {
                    toRecipients.append(addr)
                }
            }
        }

        var ccRecipients: [String] = []
        if let ccArray = msg.value(forKey: "ccRecipients") as? SBElementArray {
            for r in ccArray {
                if let recipient = r as? SBObject,
                   let addr = recipient.value(forKey: "address") as? String {
                    ccRecipients.append(addr)
                }
            }
        }

        var content: String?
        var summary: String?
        let rawContent = msg.value(forKey: "content") as? String
        if includeContent {
            content = rawContent.map { $0.count > 10_000 ? String($0.prefix(10_000)) : $0 }
        }
        if let rawContent, !rawContent.isEmpty {
            summary = String(rawContent.prefix(200)).replacingOccurrences(of: "\n", with: " ")
        }

        return MailMessage(
            id: id, subject: subject, sender: sender,
            dateSent: dateSent, dateReceived: dateReceived,
            isRead: isRead, mailbox: mailbox, account: account,
            toRecipients: toRecipients, ccRecipients: ccRecipients,
            content: content, summary: summary
        )
    }

    private func escapeAS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "\\r")
    }

    @discardableResult
    private func runAppleScript(_ script: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if errorOutput.contains("not allowed") || errorOutput.contains("not permitted") {
                throw MacKitError.permissionDenied(.mail)
            }
            if errorOutput.contains("permission") || errorOutput.contains("user interaction") {
                throw MacKitError.permissionNotDetermined(.mail)
            }
            throw MacKitError.systemError("Mail script error: \(errorOutput)")
        }

        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
