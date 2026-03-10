# mackit

Native macOS data from the command line. Access calendars, reminders, contacts, and more using Apple's native frameworks (EventKit, Contacts) with structured JSON output.

No AppleScript. No icalbuddy. Just fast, native Swift.

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

# Next event (detailed)
mackit cal next

# Just the meeting URL (pipe to open)
open $(mackit cal next --url)

# Free time slots
mackit cal free
mackit cal free --date tomorrow --duration 30m

# Filter by calendar and date range
mackit cal -c Work --from monday --to friday

# List calendars
mackit cal calendars

# JSON with field selection
mackit cal --json title,startDate,meetingURL
```

### Reminders

```bash
# Incomplete reminders (all lists)
mackit rem

# Overdue
mackit rem overdue

# Filter by list
mackit rem -l Shopping

# All lists with counts
mackit rem lists
```

### Contacts

```bash
# Search by name
mackit contacts search "John"

# Just email addresses (pipe to pbcopy)
mackit contacts search "John" --email

# Just phone numbers
mackit contacts search "John" --phone

# Upcoming birthdays
mackit contacts birthdays --days 7
```

### Focus / Do Not Disturb

```bash
# Check status
mackit focus

# Use in scripts (exit code: 0=on, 1=off)
mackit focus --quiet && echo "DND is on"
```

### Notifications

```bash
mackit notify "Build Complete" "All tests passed"
mackit notify "Deploy" "v2.1.0" --subtitle "us-east-1" --sound default
```

## Output Formats

mackit auto-detects the best output format:
- **Terminal** (interactive): human-readable text
- **Piped** (e.g., `| jq`): JSON

Override with `--format`:
```bash
mackit cal --format json
mackit cal --format text
mackit cal --format table
```

### JSON Field Selection

Select specific fields (like `gh --json`):
```bash
mackit cal --json title,startDate,meetingURL
mackit contacts search "John" --json givenName,emailAddresses
```

Invalid field names show available options:
```
Error: Unknown field 'foo'. Available fields: calendarName, endDate, id, ...
```

## Claude Code Skills

mackit ships with [Claude Code](https://claude.ai/claude-code) skills so Claude can use your calendar, reminders, and contacts natively. Install them:

```bash
# From the mackit repo
ln -s $(pwd)/skills/mackit-calendar ~/.claude/skills/mackit-calendar
ln -s $(pwd)/skills/mackit-reminders ~/.claude/skills/mackit-reminders
ln -s $(pwd)/skills/mackit-contacts ~/.claude/skills/mackit-contacts
ln -s $(pwd)/skills/mackit-focus ~/.claude/skills/mackit-focus
```

Once installed, Claude can answer questions like:
- "What's on my calendar today?"
- "Am I free at 3pm tomorrow?"
- "What's John's email?"
- "What reminders are overdue?"
- "Open my next meeting"

## Permissions

mackit uses native Apple frameworks that require permission on first use. A system dialog will appear automatically. If denied, you'll see:

```
Access denied: Calendar permission is required.
Grant access in: System Settings > Privacy & Security > Calendars
```

| Command     | Permission Required |
|------------|-------------------|
| `cal`      | Calendars         |
| `rem`      | Reminders         |
| `contacts` | Contacts          |
| `notify`   | Notifications     |
| `focus`    | None              |

## Architecture

```
Sources/
  mackit/          # CLI (swift-argument-parser commands)
  MacKitCore/      # Library (services, models, output rendering)
Tests/
  MacKitCoreTests/ # 120 tests across 14 suites
skills/            # Claude Code skills
```

Every Apple framework call is behind a protocol, making the library fully testable with mocks. `MacKitCore` can be imported as a library in other Swift projects.

## Requirements

- macOS 13 (Ventura) or later
- Swift 6.0+

## License

MIT
