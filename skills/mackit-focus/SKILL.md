---
name: mackit-focus
description: Use when checking if the user has Do Not Disturb or Focus mode enabled on macOS, or when deciding whether to send notifications. Auto-triggers on questions like "am I on DND", "is focus mode on", "should I send a notification".
---

# mackit focus

Check macOS Focus/Do Not Disturb status via `mackit focus`. No permissions required.

## Commands

```bash
# Check status (text in terminal, JSON when piped)
mackit focus

# JSON output
mackit focus --format json
# {"isEnabled":true,"mode":"Do Not Disturb"}

# Silent mode: exit code only (0=on, 1=off)
mackit focus --quiet
```

## Scripting

```bash
# Conditional on focus status
mackit focus --quiet && echo "DND is on" || echo "DND is off"

# Skip notification if DND is on
mackit focus --quiet || mackit notify "Build Done" "All tests passed"
```
