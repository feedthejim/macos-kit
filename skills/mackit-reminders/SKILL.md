---
name: mackit-reminders
description: Use when accessing the user's macOS reminders, checking what's overdue, listing reminder lists, adding/completing/deleting reminders. Auto-triggers on questions like "what reminders do I have", "what's overdue", "show my shopping list", "remind me to", "mark milk as done", "add to my shopping list".
---

# mackit reminders

Access macOS Reminders natively via `mackit rem`. Outputs JSON when piped, human text in terminal.

## Commands

```bash
# Incomplete reminders across all lists (default)
mackit rem

# Filter by list
mackit rem -l Shopping
mackit rem -l Work

# Include completed
mackit rem --completed

# Due within timeframe
mackit rem --due today
mackit rem --due tomorrow

# Overdue reminders
mackit rem overdue

# Show all lists with item counts
mackit rem lists
```

### Add reminder

```bash
mackit rem add "Buy milk" --list Shopping
mackit rem add "Review PR #456" --list Work --due tomorrow --priority high
mackit rem add "Call dentist" --due 2026-03-15 --notes "Ask about cleaning"
```

### Complete reminder (fuzzy match)

```bash
# Matches first incomplete reminder containing "milk" (case-insensitive)
mackit rem done "milk"
mackit rem done "PR"
```

### Delete reminder

```bash
mackit rem delete <reminder-id> --yes
```

### Move between lists

```bash
mackit rem move "Buy eggs" --to Groceries
```

## JSON Field Selection

```bash
mackit rem --json title,dueDate,listName,priority
```

**Available fields:** `id`, `title`, `dueDate`, `isCompleted`, `completionDate`, `priority`, `listName`, `notes`

Priority values: `none`, `high`, `medium`, `low`

## Common Workflows

**Daily review:**
```bash
mackit rem overdue
mackit rem --due today
```

**Check a specific list:**
```bash
mackit rem -l Shopping --format text
```

**Get all reminders as JSON:**
```bash
mackit rem --json title,dueDate,listName
```

## Flags Reference

| Flag | Short | Description |
|------|-------|-------------|
| `--list NAME` | `-l` | Filter by list name |
| `--completed` | | Include completed reminders |
| `--due WHEN` | | Filter by due date (today, tomorrow, ISO date) |
| `--limit N` | `-n` | Max reminders |
| `--format FMT` | | json, text, or table |
| `--json FIELDS` | | Comma-separated field names |
