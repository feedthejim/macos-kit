---
name: mackit-mcp
description: Use when setting up mackit as an MCP server for Claude Code or Claude Desktop, or when troubleshooting MCP connection issues. Also use when you want Claude to directly access macOS calendar, reminders, contacts, focus status, or send notifications without shell commands.
---

# mackit MCP Server

mackit includes a built-in MCP server that exposes calendar, reminders, contacts, focus, and notifications as tools. Once configured, Claude can access your macOS data directly.

## Setup

### Claude Code

Add to your project's `.mcp.json`:

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

Or globally in `~/.claude.json`:

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

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

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

## Available Tools

### Calendar (read)
| Tool | Description |
|------|-------------|
| `calendar_list` | List events (from, to, calendar, limit, includePast) |
| `calendar_next` | Next upcoming event with meeting URL |
| `calendar_free` | Free time slots (date, minDuration in minutes) |
| `calendar_calendars` | All calendars with names and colors |

### Calendar (write)
| Tool | Description |
|------|-------------|
| `calendar_create` | Create event (title, date, startTime, endTime, calendar, location, notes) |
| `calendar_delete` | Delete event by ID |
| `calendar_update` | Update event fields (title, notes, location) |
| `calendar_move` | Reschedule event (date, startTime, endTime) |

### Reminders (read)
| Tool | Description |
|------|-------------|
| `reminders_list` | List reminders (list, includeCompleted, due, limit) |
| `reminders_overdue` | All overdue reminders |
| `reminders_lists` | All lists with item counts |

### Reminders (write)
| Tool | Description |
|------|-------------|
| `reminders_add` | Create reminder (title, list, due, priority, notes) |
| `reminders_complete` | Complete by title match or ID |
| `reminders_delete` | Delete by ID |
| `reminders_move` | Move to another list by title match |

### Contacts
| Tool | Description |
|------|-------------|
| `contacts_search` | Search by name, email, phone (query, limit) |
| `contacts_birthdays` | Upcoming birthdays (days) |

### System
| Tool | Description |
|------|-------------|
| `focus_status` | Check Focus/DND mode |
| `notify_send` | Send macOS notification (title, body, subtitle, sound) |

## Permissions

First use of calendar/reminders/contacts tools will trigger a macOS permission prompt. If denied, the tool returns an error with instructions to grant access in System Settings.

## Troubleshooting

**"command not found":** Use the full path `/usr/local/bin/mackit` in the config.

**No permission prompt:** Reset with `tccutil reset Calendar` then retry.

**Test the server manually:**
```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | mackit mcp
```
