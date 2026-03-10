# mackit

Native macOS data from the command line. Read and write calendars, reminders, contacts, mail, and more using Apple's native frameworks (EventKit, Contacts, ScriptingBridge) with structured JSON output. Includes an MCP server for AI agent integration.

No icalbuddy. Just fast, native Swift.

## Install

**One-liner:**
```bash
curl -fsSL https://github.com/feedthejim/macos-kit/releases/latest/download/mackit-macos-universal.tar.gz | tar xz -C /usr/local/bin
```

**Homebrew:**
```bash
brew install feedthejim/tap/mackit
```

**From source:**
```bash
git clone https://github.com/feedthejim/macos-kit.git && cd macos-kit && swift build -c release && cp .build/release/mackit /usr/local/bin/
```

## Usage

### Calendar

```bash
# Today's remaining events
mackit cal

# Tomorrow / this week
mackit cal tomorrow
mackit cal week

# Next event + meeting URL
mackit cal next
open $(mackit cal next --url)

# Free time slots
mackit cal free --date tomorrow --duration 30m

# Filter by calendar and date range
mackit cal -c Work --from monday --to friday

# Create event
mackit cal create "Coffee with Sarah" --date tomorrow --from 3pm --to 3:30pm
mackit cal create "Design Review" --date friday --from 2pm --to 3pm -c Work --location "Room 4"

# Reschedule
mackit cal move <event-id> --date friday --from 3pm

# Update / delete
mackit cal update <event-id> --notes "Bring laptop"
mackit cal delete <event-id> --yes

# JSON with field selection
mackit cal --json title,startDate,meetingURL
```

### Reminders

```bash
# List (incomplete by default)
mackit rem
mackit rem -l Shopping
mackit rem overdue

# Add
mackit rem add "Buy milk" --list Shopping
mackit rem add "Review PR" --list Work --due tomorrow --priority high

# Complete (fuzzy title match)
mackit rem done "milk"

# Move between lists
mackit rem move "Buy eggs" --to Groceries

# Delete
mackit rem delete <id> --yes
```

### Contacts

```bash
mackit contacts search "John"
mackit contacts search "John" --email        # Just emails, one per line
mackit contacts search "John" --phone        # Just phones
mackit contacts birthdays --days 7
```

### Mail

```bash
# List recent messages (default: INBOX)
mackit mail
mackit mail list --unread
mackit mail list -m "Sent Mail" -a Gmail -n 5

# Read a message
mackit mail read <id> -m INBOX -a iCloud

# Search
mackit mail search "invoice"
mackit mail search "meeting" -a Gmail -n 10

# Mailboxes and accounts
mackit mail mailboxes
mackit mail mailboxes -a iCloud
mackit mail accounts

# Send
mackit mail send --to bob@test.com --subject "Hello" --body "Hi Bob"
mackit mail send --to a@test.com --cc b@test.com --subject "FYI" --body "See this"

# Mark read/unread
mackit mail mark-read <id> -a iCloud
mackit mail mark-unread <id> -a iCloud

# Move / delete
mackit mail move <id> --to Archive -a iCloud
mackit mail delete <id> -a iCloud --yes

# JSON with field selection
mackit mail list --json id,subject,sender,isRead
```

### Focus / Do Not Disturb

```bash
mackit focus
mackit focus --quiet && echo "DND is on"     # Exit code for scripting
```

### Notifications

```bash
mackit notify "Build Complete" "All tests passed"
mackit notify "Deploy" "v2.1.0" --subtitle "us-east-1" --sound default
```

## MCP Server

mackit includes a built-in MCP server for AI agent integration (Claude Code, Claude Desktop, etc.).

### Setup

**Claude Code** (project `.mcp.json`):
```json
{
  "mcpServers": {
    "mackit": {
      "command": "mackit",
      "args": ["mcp"]
    }
  }
}
```

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "mackit": {
      "command": "/usr/local/bin/mackit",
      "args": ["mcp"]
    }
  }
}
```

### Available MCP Tools

| Tool | Description |
|------|-------------|
| `calendar_list` | List events with date range, calendar filter |
| `calendar_next` | Next upcoming event with meeting URL |
| `calendar_free` | Free time slots for scheduling |
| `calendar_calendars` | List all calendars |
| `calendar_create` | Create a calendar event |
| `calendar_delete` | Delete an event |
| `calendar_update` | Update event fields |
| `calendar_move` | Reschedule an event |
| `reminders_list` | List reminders by list, status, due date |
| `reminders_overdue` | All overdue reminders |
| `reminders_lists` | List all reminder lists with counts |
| `reminders_add` | Create a reminder |
| `reminders_complete` | Complete by title match or ID |
| `reminders_delete` | Delete a reminder |
| `reminders_move` | Move to another list |
| `contacts_search` | Search by name, email, phone |
| `contacts_birthdays` | Upcoming birthdays |
| `mail_list` | List messages with filters, compact view |
| `mail_search` | Search messages by keyword |
| `mail_read` | Read full message content |
| `mail_mailboxes` | List mailboxes with unread counts |
| `mail_accounts` | List mail accounts |
| `mail_send` | Send an email |
| `mail_mark_read` | Mark message as read |
| `mail_mark_unread` | Mark message as unread |
| `mail_move` | Move message to another mailbox |
| `mail_delete` | Delete a message |
| `focus_status` | Check Focus/DND mode |
| `notify_send` | Send a macOS notification |

## Output Formats

Auto-detects: text in terminal, JSON when piped. Override with `--format json|text|table`.

**JSON field selection** (like `gh --json`):
```bash
mackit cal --json title,startDate,meetingURL
mackit contacts search "John" --json givenName,emailAddresses
```

## Permissions

| Command     | Permission |
|------------|-----------|
| `cal`      | Calendars |
| `rem`      | Reminders |
| `contacts` | Contacts  |
| `notify`   | Notifications |
| `mail`     | Automation (Mail.app) |
| `focus`    | None      |
| `mcp`      | All (on demand) |

## Architecture

```
Sources/
  mackit/          # CLI commands (swift-argument-parser)
  MacKitCore/      # Library (services, models, MCP server)
Tests/             # 225 tests across 28 suites
skills/            # Claude Code skills
```

Protocol-based services with full mock support. `MacKitCore` is importable as a library.

## Requirements

- macOS 13 (Ventura) or later
- Swift 6.0+

## License

MIT
