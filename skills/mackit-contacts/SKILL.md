---
name: mackit-contacts
description: Use when looking up contact information, finding someone's email or phone number, checking upcoming birthdays, or searching the user's macOS address book. Auto-triggers on questions like "what's John's email", "find contact", "who has a birthday", "look up phone number".
---

# mackit contacts

Access macOS Contacts natively via `mackit contacts`. Outputs JSON when piped, human text in terminal.

## Commands

### Search

```bash
# Search by name
mackit contacts search "John"

# Just email addresses (one per line, pipe-friendly)
mackit contacts search "John" --email

# Just phone numbers
mackit contacts search "John" --phone

# Filter by organization
mackit contacts search "John" --org "Apple"

# Limit results
mackit contacts search "John" -n 3
```

### Birthdays

```bash
# Upcoming birthdays (default: 30 days)
mackit contacts birthdays

# This week
mackit contacts birthdays --days 7
```

## JSON Field Selection

```bash
mackit contacts search "John" --json givenName,familyName,emailAddresses
```

**Available fields:** `id`, `givenName`, `familyName`, `organizationName`, `emailAddresses`, `phoneNumbers`, `birthday`, `note`

## Common Workflows

**Quick email lookup (pipe to clipboard):**
```bash
mackit contacts search "John Appleseed" --email | pbcopy
```

**Get someone's phone:**
```bash
mackit contacts search "Jane" --phone
```

**Full contact card:**
```bash
mackit contacts search "John" --format text
```

## Flags Reference

| Flag | Short | Description |
|------|-------|-------------|
| `--email` | | Output only email addresses (one per line) |
| `--phone` | | Output only phone numbers (one per line) |
| `--org NAME` | | Filter by organization |
| `--days N` | | (birthdays) Days ahead to search (default: 30) |
| `--limit N` | `-l` | Max results |
| `--format FMT` | | json, text, or table |
| `--json FIELDS` | | Comma-separated field names |
