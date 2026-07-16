import Foundation
import ScriptingBridge
import Darwin

public final class LiveMailService: MailServiceProtocol, @unchecked Sendable {
    private static let appleEventTimeout = 30
    private let app: SBApplication?

    public init() {
        self.app = SBApplication(bundleIdentifier: "com.apple.mail")
        self.app?.timeout = Self.appleEventTimeout
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

    public func queryMessages(_ query: MailQuery) async throws -> MailPage {
        try await ensureRunning()
        guard query.limit > 0 else {
            return MailPage(messages: [], offset: query.offset)
        }
        let mailboxesToSearch = findMailboxes(named: query.mailbox, account: query.account)
        guard !mailboxesToSearch.isEmpty else {
            try throwLastApplicationError()
            throw MacKitError.notFound("No matching mailboxes")
        }

        let fetchCount = query.offset + min(query.limit, 200) + 1
        var candidates: [MailMessage] = []
        var warnings: [String] = []
        var firstError: Error?
        var successfulMailboxes = 0

        for (_, mailbox, account) in mailboxesToSearch {
            try Task.checkCancellation()
            do {
                candidates.append(contentsOf: try bulkQueryMetadata(
                    mailbox: mailbox, account: account, count: fetchCount, query: query
                ))
                successfulMailboxes += 1
            } catch {
                firstError = firstError ?? error
                warnings.append("Skipped \(account)/\(mailbox): \(error.localizedDescription)")
            }
        }
        if successfulMailboxes == 0, let firstError { throw firstError }

        candidates.sort { $0.dateReceived > $1.dateReceived }
        let remaining = Array(candidates.dropFirst(query.offset))
        let hasMore = remaining.count > query.limit
        var messages = Array(remaining.prefix(query.limit))

        if query.includeDetails {
            for index in messages.indices {
                try Task.checkCancellation()
                do {
                    messages[index] = try await getMessage(
                        id: messages[index].id,
                        mailbox: messages[index].mailbox,
                        account: messages[index].account
                    )
                } catch {
                    warnings.append(
                        "Details unavailable for message \(messages[index].id): \(error.localizedDescription)"
                    )
                }
            }
        }

        return MailPage(
            messages: messages,
            offset: query.offset,
            nextOffset: hasMore ? query.offset + messages.count : nil,
            isPartial: !warnings.isEmpty,
            warnings: warnings
        )
    }

    public func accounts() async throws -> [MailAccount] {
        try await ensureRunning()
        guard let sbAccounts = try mailApp.value(forKey: "accounts") as? SBElementArray else {
            try throwLastApplicationError()
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
            try throwLastApplicationError()
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

    public func messages(mailbox: String?, account: String?, limit: Int, unreadOnly: Bool, includeDetails: Bool) async throws -> [MailMessage] {
        try await ensureRunning()
        guard limit > 0 else { return [] }
        let targetMailbox = mailbox ?? "INBOX"
        guard let sbMailbox = findMailbox(named: targetMailbox, account: account) else {
            try throwLastApplicationError()
            throw MacKitError.notFound("Mailbox '\(targetMailbox)'" + (account.map { " in account '\($0)'" } ?? ""))
        }
        let acctName = account ?? accountName(for: sbMailbox)
        guard let sbMessages = sbMailbox.value(forKey: "messages") as? SBElementArray else {
            try throwLastApplicationError()
            return []
        }

        var result: [MailMessage] = []
        if unreadOnly {
            if !includeDetails {
                return try bulkMessageMetadata(
                    mailbox: targetMailbox,
                    account: acctName,
                    count: limit,
                    filter: .unread
                )
            }
            let unreadMessages = sbMessages.filtered(using: NSPredicate(format: "readStatus == NO"))
            try throwLastApplicationError()
            let resultCount = min(unreadMessages.count, limit)
            for case let msg as SBObject in unreadMessages.prefix(resultCount) {
                result.append(mapMessage(msg, mailbox: targetMailbox, account: acctName))
            }
        } else {
            let resultCount = min(sbMessages.count, limit)
            if !includeDetails {
                return try bulkMessageMetadata(
                    mailbox: targetMailbox,
                    account: acctName,
                    count: resultCount,
                    filter: .none
                )
            }
            for i in 0..<resultCount {
                guard let msg = sbMessages.object(at: i) as? SBObject else { continue }
                result.append(mapMessage(msg, mailbox: targetMailbox, account: acctName))
            }
        }
        return result
    }

    public func searchMessages(query: String, mailbox: String?, account: String?, limit: Int, includeDetails: Bool) async throws -> [MailMessage] {
        try await ensureRunning()
        guard limit > 0 else { return [] }
        var result: [MailMessage] = []
        let predicate = NSPredicate(
            format: "(subject CONTAINS[c] %@) OR (sender CONTAINS[c] %@)",
            query, query
        )

        let mailboxesToSearch: [(SBObject, String, String)] = findMailboxes(named: mailbox, account: account)
        if mailboxesToSearch.isEmpty {
            try throwLastApplicationError()
        }

        for (sbMailbox, mbName, acctName) in mailboxesToSearch {
            guard let sbMessages = sbMailbox.value(forKey: "messages") as? SBElementArray else {
                try throwLastApplicationError()
                continue
            }

            if !includeDetails {
                result.append(contentsOf: try bulkMessageMetadata(
                    mailbox: mbName,
                    account: acctName,
                    count: limit - result.count,
                    filter: .search(query)
                ))
            } else {
                // SBElementArray translates this predicate into a Mail.app `whose`
                // query instead of fetching and scanning messages in this process.
                let matches = sbMessages.filtered(using: predicate)
                try throwLastApplicationError()
                let resultCount = min(matches.count, limit - result.count)
                for case let msg as SBObject in matches.prefix(resultCount) {
                    result.append(mapMessage(msg, mailbox: mbName, account: acctName))
                }
            }
            if result.count >= limit { return result }
        }
        return result
    }

    public func getMessage(id: String, mailbox: String, account: String) async throws -> MailMessage {
        try await ensureRunning()
        guard let sbMailbox = findMailbox(named: mailbox, account: account) else {
            try throwLastApplicationError()
            throw MacKitError.notFound("Mailbox '\(mailbox)' in account '\(account)'")
        }
        guard let sbMessages = sbMailbox.value(forKey: "messages") as? SBElementArray else {
            try throwLastApplicationError()
            throw MacKitError.notFound("Message \(id)")
        }

        guard let numericID = Int(id),
              let msg = sbMessages.object(withID: numericID) as? SBObject,
              "\(msg.value(forKey: "id") ?? "")" == id else {
            try throwLastApplicationError()
            throw MacKitError.notFound("Message \(id)")
        }
        return mapMessage(msg, mailbox: mailbox, account: account)
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
        let numericID = try mailMessageID(id)
        // Use AppleScript for move since KVC can't express the "move to" target
        let script = """
            tell application "Mail"
                set targetMailbox to mailbox "\(escapeAS(toMailbox))" of account "\(escapeAS(account))"
                set targetAccount to account "\(escapeAS(account))"
                set targetMessage to first message of mailbox "\(escapeAS(fromMailbox))" of targetAccount whose id is \(numericID)
                move targetMessage to targetMailbox
                return "ok"
            end tell
            """
        try runAppleScript(script)
    }

    public func deleteMessage(id: String, mailbox: String, account: String) async throws {
        try await ensureRunning()
        let numericID = try mailMessageID(id)
        let script = """
            tell application "Mail"
                set targetAccount to account "\(escapeAS(account))"
                set targetMessage to first message of mailbox "\(escapeAS(mailbox))" of targetAccount whose id is \(numericID)
                delete targetMessage
                return "ok"
            end tell
            """
        try runAppleScript(script)
    }

    // MARK: - Helpers

    private func bulkMessageMetadata(
        mailbox: String,
        account: String,
        count: Int,
        filter: MailMetadataFilter
    ) throws -> [MailMessage] {
        guard count > 0 else { return [] }
        let messageExpression: String = switch filter {
        case .none:
            "targetMailbox.messages.slice(0, \(count - 1))()"
        case .unread:
            "targetMailbox.messages.whose({readStatus: false})().slice(0, \(count))"
        case .search(let query):
            "targetMailbox.messages.whose({_or: [{subject: {_contains: \(jsString(query))}}, {sender: {_contains: \(jsString(query))}}]})().slice(0, \(count))"
        }
        let scriptSource = """
            const Mail = Application("Mail");
            const account = Mail.accounts.byName(\(jsString(account)));
            const targetMailbox = account.mailboxes.byName(\(jsString(mailbox)));
            var messages = [];
            try {
                messages = \(messageExpression);
            } catch (error) {
                if (!String(error).includes("Invalid index")) throw error;
            }
            JSON.stringify(messages.map(message => {
                const received = message.dateReceived();
                return {
                    id: String(message.id()),
                    subject: message.subject() || "",
                    sender: message.sender() || "",
                    dateReceived: received ? received.getTime() / 1000 : null,
                    isRead: message.readStatus()
                };
            }));
            """
        let output = try runJavaScript(scriptSource)
        let metadata = try JSONDecoder().decode([MailMetadataDTO].self, from: Data(output.utf8))
        return metadata.map { item in
            MailMessage(
                id: item.id,
                subject: item.subject,
                sender: item.sender,
                dateReceived: item.dateReceived.map(Date.init(timeIntervalSince1970:)) ?? Date(),
                isRead: item.isRead,
                mailbox: mailbox,
                account: account
            )
        }
    }

    private func bulkQueryMetadata(
        mailbox: String,
        account: String,
        count: Int,
        query: MailQuery
    ) throws -> [MailMessage] {
        var conditions: [String] = []
        if query.unreadOnly { conditions.append("{readStatus: false}") }
        if let search = query.search, !search.isEmpty {
            conditions.append(
                "{_or: [{subject: {_contains: \(jsString(search))}}, {sender: {_contains: \(jsString(search))}}]}"
            )
        }
        if let sender = query.sender, !sender.isEmpty {
            conditions.append("{sender: {_contains: \(jsString(sender))}}")
        }
        if let after = query.receivedAfter {
            conditions.append(
                "{dateReceived: {_greaterThan: new Date(\(Int(after.timeIntervalSince1970 * 1_000)))}}"
            )
        }
        if let before = query.receivedBefore {
            conditions.append(
                "{dateReceived: {_lessThan: new Date(\(Int(before.timeIntervalSince1970 * 1_000)))}}"
            )
        }
        let selection: String
        if conditions.isEmpty {
            selection = "targetMailbox.messages.slice(0, \(max(0, count - 1)))()"
        } else {
            let predicate = conditions.count == 1 ? conditions[0] : "{_and: [\(conditions.joined(separator: ", "))]}"
            selection = "targetMailbox.messages.whose(\(predicate))().slice(0, \(count))"
        }
        var optionalProperties: [String] = []
        if query.requestedFields.contains("messageId") {
            optionalProperties.append("messageId: message.messageId() || null")
        }
        if query.requestedFields.contains("replyTo") {
            optionalProperties.append("replyTo: message.replyTo() || null")
        }
        if query.requestedFields.contains("messageSize") {
            optionalProperties.append("messageSize: message.messageSize() || null")
        }
        let optionalPropertySource = optionalProperties.isEmpty
            ? "" : ",\n                    " + optionalProperties.joined(separator: ",\n                    ")
        let scriptSource = """
            const Mail = Application("Mail");
            const account = Mail.accounts.byName(\(jsString(account)));
            const targetMailbox = account.mailboxes.byName(\(jsString(mailbox)));
            var messages = [];
            try {
                messages = \(selection);
            } catch (error) {
                if (!String(error).includes("Invalid index")) throw error;
            }
            JSON.stringify(messages.map(message => {
                const received = message.dateReceived();
                return {
                    id: String(message.id()),
                    subject: message.subject() || "",
                    sender: message.sender() || "",
                    dateReceived: received ? received.getTime() / 1000 : null,
                    isRead: message.readStatus()\(optionalPropertySource)
                };
            }));
            """
        let output = try runJavaScript(scriptSource, timeoutSeconds: 10)
        let metadata = try JSONDecoder().decode([MailMetadataDTO].self, from: Data(output.utf8))
        return metadata.map { item in
            MailMessage(
                id: item.id,
                subject: item.subject,
                sender: item.sender,
                dateReceived: item.dateReceived.map(Date.init(timeIntervalSince1970:)) ?? Date(),
                isRead: item.isRead,
                mailbox: mailbox,
                account: account,
                messageId: item.messageId,
                replyTo: item.replyTo,
                messageSize: item.messageSize
            )
        }
    }

    private enum MailMetadataFilter {
        case none
        case unread
        case search(String)
    }

    private struct MailMetadataDTO: Decodable {
        let id: String
        let subject: String
        let sender: String
        let dateReceived: TimeInterval?
        let isRead: Bool
        let messageId: String?
        let replyTo: String?
        let messageSize: Int?
    }

    private func throwLastApplicationError() throws {
        guard let error = app?.lastError() as NSError? else { return }
        switch error.code {
        case -1743:
            throw MacKitError.permissionDenied(.mail)
        case -1744:
            throw MacKitError.permissionNotDetermined(.mail)
        case -1712:
            throw MacKitError.systemError(
                "Mail.app did not respond within \(Self.appleEventTimeout) seconds. "
                + "Check System Settings > Privacy & Security > Automation, then retry with a smaller --limit or a specific --account."
            )
        default:
            throw MacKitError.systemError("Mail.app error: \(error.localizedDescription)")
        }
    }

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
        guard let numericID = Int(id),
              let msg = sbMessages.object(withID: numericID) as? SBObject,
              "\(msg.value(forKey: "id") ?? "")" == id else {
            try throwLastApplicationError()
            throw MacKitError.notFound("Message \(id)")
        }
        return msg
    }

    private func accountName(for mailbox: SBObject) -> String {
        // Walk up to find account name
        if let acct = mailbox.value(forKey: "account") as? SBObject {
            return acct.value(forKey: "name") as? String ?? ""
        }
        return ""
    }

    /// Maps only the fields needed by list and search results. Each ScriptingBridge
    /// property access is a separate Apple event, so recipients and message bodies
    /// must stay out of this hot path.
    private func mapMessageMetadata(
        _ msg: SBObject,
        mailbox: String,
        account: String,
        knownReadStatus: Bool? = nil
    ) -> MailMessage {
        let id = "\(msg.value(forKey: "id") ?? "")"
        let subject = msg.value(forKey: "subject") as? String ?? ""
        let sender = msg.value(forKey: "sender") as? String ?? ""
        let dateReceived = msg.value(forKey: "dateReceived") as? Date ?? Date()
        let isRead = knownReadStatus ?? (msg.value(forKey: "readStatus") as? Bool ?? false)

        return MailMessage(
            id: id, subject: subject, sender: sender,
            dateReceived: dateReceived,
            isRead: isRead, mailbox: mailbox, account: account
        )
    }

    private func mapMessage(_ msg: SBObject, mailbox: String, account: String) -> MailMessage {
        let metadata = mapMessageMetadata(msg, mailbox: mailbox, account: account)
        let dateSent = msg.value(forKey: "dateSent") as? Date
        let messageId = msg.value(forKey: "messageId") as? String
        let replyTo = msg.value(forKey: "replyTo") as? String
        let messageSize = msg.value(forKey: "messageSize") as? Int

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

        let rawContent = msg.value(forKey: "content") as? String
        let content = rawContent.map { $0.count > 10_000 ? String($0.prefix(10_000)) : $0 }
        var summary: String?
        if let rawContent, !rawContent.isEmpty {
            summary = String(rawContent.prefix(200)).replacingOccurrences(of: "\n", with: " ")
        }

        var attachments: [MailAttachment] = []
        if let attachmentArray = msg.value(forKey: "mailAttachments") as? SBElementArray {
            for case let attachment as SBObject in attachmentArray {
                attachments.append(MailAttachment(
                    id: "\(attachment.value(forKey: "id") ?? "")",
                    name: attachment.value(forKey: "name") as? String ?? "Attachment",
                    mimeType: attachment.value(forKey: "mimeType") as? String,
                    sizeBytes: attachment.value(forKey: "fileSize") as? Int ?? 0,
                    isDownloaded: attachment.value(forKey: "downloaded") as? Bool ?? false
                ))
            }
        }

        return MailMessage(
            id: metadata.id, subject: metadata.subject, sender: metadata.sender,
            dateSent: dateSent, dateReceived: metadata.dateReceived,
            isRead: metadata.isRead, mailbox: metadata.mailbox, account: metadata.account,
            toRecipients: toRecipients, ccRecipients: ccRecipients,
            messageId: messageId, replyTo: replyTo, messageSize: messageSize,
            attachmentCount: attachments.count, attachments: attachments,
            content: content, summary: summary
        )
    }

    private func escapeAS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func mailMessageID(_ id: String) throws -> Int {
        guard let numericID = Int(id) else {
            throw MacKitError.notFound("Message \(id)")
        }
        return numericID
    }

    private func jsString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return encoded
    }

    @discardableResult
    private func runAppleScript(_ script: String) throws -> String {
        let timedScript = "with timeout of \(Self.appleEventTimeout) seconds\n\(script)\nend timeout"
        return try runScript(arguments: ["-e", timedScript])
    }

    private func runJavaScript(_ script: String, timeoutSeconds: Int = 30) throws -> String {
        try runScript(arguments: ["-l", "JavaScript", "-e", script], timeoutSeconds: timeoutSeconds)
    }

    private func runScript(arguments: [String], timeoutSeconds: Int = 35) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = arguments

        let id = UUID().uuidString
        let tempDirectory = FileManager.default.temporaryDirectory
        let stdoutURL = tempDirectory.appendingPathComponent("mackit-\(id).stdout")
        let stderrURL = tempDirectory.appendingPathComponent("mackit-\(id).stderr")
        _ = FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        task.standardOutput = stdout
        task.standardError = stderr

        let completion = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in completion.signal() }
        try task.run()
        if completion.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut {
            task.terminate()
            if completion.wait(timeout: .now() + 1) == .timedOut {
                kill(task.processIdentifier, SIGKILL)
                _ = completion.wait(timeout: .now() + 1)
            }
            try? stdout.close()
            try? stderr.close()
            throw MacKitError.systemError(
                "Mail.app did not respond within \(timeoutSeconds) seconds. "
                + "Check System Settings > Privacy & Security > Automation and try again."
            )
        }
        try stdout.close()
        try stderr.close()

        if task.terminationStatus != 0 {
            let errorOutput = String(
                data: (try? Data(contentsOf: stderrURL)) ?? Data(), encoding: .utf8
            ) ?? ""
            if errorOutput.contains("not allowed") || errorOutput.contains("not permitted") {
                throw MacKitError.permissionDenied(.mail)
            }
            if errorOutput.contains("permission") || errorOutput.contains("user interaction") {
                throw MacKitError.permissionNotDetermined(.mail)
            }
            throw MacKitError.systemError("Mail script error: \(errorOutput)")
        }

        return String(data: (try? Data(contentsOf: stdoutURL)) ?? Data(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
