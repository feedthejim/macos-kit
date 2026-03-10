---
name: mackit-mail
description: Use when reading, searching, or sending email via Mail.app, listing mailboxes or accounts, marking messages read/unread, moving or deleting messages. Auto-triggers on questions like "check my email", "send an email", "list mailboxes", "search mail for invoice", "mark as read".
---

# mackit mail

Access macOS Mail.app via `mackit mail`. Uses ScriptingBridge for reads and AppleScript for writes. Requires Mail.app to be running (auto-launched if needed). Outputs JSON when piped, human text in terminal.

## Commands

### List Messages

```bash
# Recent INBOX messages (default)
mackit mail
mackit mail list

# Unread only
mackit mail list --unread

# Specific mailbox and account
mackit mail list -m "Sent Mail" -a Gmail

# Limit results
mackit mail list -n 5
```

### Read a Message

```bash
# Full message content (get IDs from list --json id,subject)
mackit mail read <id> -m INBOX -a iCloud
```

### Search

```bash
# Search subject and sender
mackit mail search "invoice"
mackit mail search "meeting" -m "All Mail" -a Gmail -n 10
```

### Mailboxes & Accounts

```bash
mackit mail mailboxes
mackit mail mailboxes -a iCloud
mackit mail accounts
```

### Send

```bash
mackit mail send --to bob@test.com --subject "Hello" --body "Hi Bob"
mackit mail send --to a@test.com --cc b@test.com --subject "FYI" --body "Details"

# Preview without sending
mackit mail send --to bob@test.com --subject "Test" --body "Hi" --dry-run
```

### Mark Read / Unread

```bash
mackit mail mark-read <id> -a iCloud
mackit mail mark-unread <id> -a iCloud
```

### Move / Delete

```bash
mackit mail move <id> --to Archive -m INBOX -a iCloud
mackit mail delete <id> -a iCloud --yes    # --yes required
```

## JSON Field Selection

```bash
mackit mail list --json id,subject,sender,isRead
mackit mail search "invoice" --json subject,sender,dateReceived
```

**Available fields:** `id`, `subject`, `sender`, `dateSent`, `dateReceived`, `isRead`, `mailbox`, `account`, `toRecipients`, `ccRecipients`, `content`, `summary`

## Common Workflows

**Check unread mail:**
```bash
mackit mail list --unread -n 10
```

**Find a specific email:**
```bash
mackit mail search "receipt" -n 5
```

**Read and mark as read:**
```bash
mackit mail read <id> -m INBOX -a iCloud
mackit mail mark-read <id> -a iCloud
```

## Permissions

Mail requires macOS Automation permission. On first use, a system dialog will prompt to allow the terminal to control Mail.app. If denied, grant access in System Settings > Privacy & Security > Automation.

## Flags Reference

| Flag | Short | Description |
|------|-------|-------------|
| `--mailbox NAME` | `-m` | Mailbox name (default: INBOX) |
| `--account NAME` | `-a` | Account name |
| `--unread` | | Show only unread messages |
| `--limit N` | `-n` | Max results (default: 25) |
| `--to ADDR` | | Recipient (repeatable) |
| `--cc ADDR` | | CC recipient (repeatable) |
| `--bcc ADDR` | | BCC recipient (repeatable) |
| `--subject TEXT` | | Email subject |
| `--body TEXT` | | Email body |
| `--from ADDR` | | Send from specific account |
| `--dry-run` | | Preview without sending |
| `--yes` | | Confirm destructive operation |
| `--format FMT` | | json, text, or table |
| `--json FIELDS` | | Comma-separated field names |
