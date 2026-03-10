---
name: mackit-reminders
description: Use when accessing the user's macOS reminders, checking what's overdue, listing reminder lists, or reviewing tasks. Auto-triggers on questions like "what reminders do I have", "what's overdue", "show my shopping list", "what tasks are due".
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
