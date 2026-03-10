---
name: mackit-calendar
description: Use when accessing the user's macOS calendar, checking upcoming meetings, finding meeting links, checking availability, creating/deleting/rescheduling events, or scheduling around existing events. Auto-triggers on questions like "what's on my calendar", "am I free at", "what's my next meeting", "join my next call", "schedule a meeting", "cancel my 3pm", "move my meeting".
---

# mackit calendar

Access macOS calendar events natively via `mackit cal`. Outputs JSON when piped, human text in terminal.

## Commands

```bash
# Today's remaining events (default)
mackit cal

# Tomorrow / this week
mackit cal tomorrow
mackit cal week

# Date range
mackit cal --from monday --to friday
mackit cal --from 2026-03-15 --to 2026-03-20

# Filter by calendar
mackit cal -c Work
mackit cal -c Work -c Personal

# Limit results
mackit cal -n 5
```

### Next event

```bash
# Detailed view of next event
mackit cal next

# Just the meeting URL (composable)
mackit cal next --url

# Open next meeting directly
open $(mackit cal next --url)
```

### Free time slots

```bash
# Free slots today (working hours 9-5)
mackit cal free

# Tomorrow, minimum 30 min slots
mackit cal free --date tomorrow --duration 30m

# Check if free for 1 hour
mackit cal free --duration 1h
```

### Create event

```bash
# Basic event
mackit cal create "Coffee with Sarah" --date tomorrow --from 3pm --to 3:30pm

# With calendar, location, notes
mackit cal create "Design Review" --date friday --from 2pm --to 3pm \
  -c Work --location "Room 4" --notes "Bring mockups"

# All-day event
mackit cal create "Team Offsite" --date 2026-03-20 --all-day

# Preview without creating
mackit cal create "Test" --date tomorrow --from 1pm --to 2pm --dry-run
```

### Delete event

```bash
# Shows event details, asks for confirmation
mackit cal delete <event-id>

# Skip confirmation
mackit cal delete <event-id> --yes
```

### Reschedule event

```bash
# Move to new date (preserves time and duration)
mackit cal move <event-id> --date friday

# Move to new time
mackit cal move <event-id> --from 3pm --to 4pm

# Move to new date and time
mackit cal move <event-id> --date monday --from 10am --to 11am
```

### Update event

```bash
mackit cal update <event-id> --notes "Updated agenda"
mackit cal update <event-id> --title "New Title" --location "Room 5"
```

### List calendars

```bash
mackit cal calendars
```

## JSON Field Selection

Select specific fields with `--json`:

```bash
mackit cal --json title,startDate,meetingURL
mackit cal --json title,calendarName,location
```

**Available fields:** `id`, `title`, `startDate`, `endDate`, `isAllDay`, `location`, `calendarName`, `calendarColor`, `status`, `organizer`, `notes`, `url`, `meetingURL`

The `meetingURL` field automatically extracts Zoom, Google Meet, Teams, Webex, and Around links from event notes/location/URL.

## Common Workflows

**Morning planning:**
```bash
mackit cal --format text
```

**"Am I free at 3pm tomorrow?":**
```bash
mackit cal free --date tomorrow --duration 30m
```

**Get meeting link for current/next call:**
```bash
mackit cal next --url
```

**List today's meetings as JSON for processing:**
```bash
mackit cal --json title,startDate,endDate,meetingURL
```

## Output Formats

- `--format text` (default in terminal): human-readable with relative times ("in 25 min")
- `--format json` (default when piped): structured JSON with ISO 8601 dates
- `--format table`: aligned columns

## Flags Reference

| Flag | Short | Description |
|------|-------|-------------|
| `--from DATE` | | Start date (ISO 8601, today, tomorrow, monday, "next week") |
| `--to DATE` | | End date |
| `--calendar NAME` | `-c` | Filter by calendar (repeatable) |
| `--limit N` | `-l` | Max events |
| `--include-past` | | Show past events today |
| `--format FMT` | | json, text, or table |
| `--json FIELDS` | | Comma-separated field names |
| `--url` | | (next only) Print just the meeting URL |
| `--date DATE` | | (free only) Date to check |
| `--duration DUR` | | (free only) Minimum slot: 30m, 1h, etc. |
