# mackit Development Guide

## Project

Native macOS CLI tool for accessing calendar, reminders, contacts, focus status, and notifications. Includes MCP server for AI agent integration.

**Binary:** `mackit` | **Package:** `macos-kit` | **Language:** Swift 6.0 | **Min OS:** macOS 13

## Architecture

Two-target design:
- `MacKitCore` (library): services, models, output rendering, MCP server. All Apple framework calls behind protocols for testability.
- `mackit` (executable): thin CLI wrapper using swift-argument-parser.

Key patterns:
- **Protocol-based services**: `CalendarServiceProtocol` + `LiveCalendarService` + `MockCalendarService`
- **Sendable models**: Map non-Sendable Apple types (EKReminder, CNContact) to Sendable structs inside closures before crossing async boundaries
- **`@preconcurrency import EventKit`**: Required for reminder fetch callbacks in Swift 6
- **Output auto-detection**: `isatty(STDOUT_FILENO)` chooses text vs JSON
- **FieldSelectable protocol**: Static `availableFields` list for `--json` field validation (avoids optional-nil-key problem)

## Build & Test

```bash
swift build              # Debug build
swift build -c release   # Release build
swift test               # Run all 147 tests (no TCC permissions needed)
mackit --version         # Verify installed binary
```

Tests use mocks exclusively. No calendar/contacts/reminders access needed in CI.

## Directory Structure

```
Sources/mackit/Commands/        # CLI commands (one file per domain + write commands)
Sources/MacKitCore/Services/    # Protocols + Live implementations
Sources/MacKitCore/Models/      # Codable structs (CalendarEvent, Reminder, Contact, etc.)
Sources/MacKitCore/Output/      # OutputRenderer, FieldSelection, TextRepresentable
Sources/MacKitCore/MCP/         # MCPServer, MCPTools, MCPTypes
Sources/MacKitCore/Utilities/   # DateParsing, RelativeTime, DurationFormatter, MeetingURLExtractor
Sources/MacKitCore/Errors/      # MacKitError, PermissionDomain
Tests/MacKitCoreTests/          # Mirror structure with Mocks/ directory
skills/                         # Claude Code skills (mackit-calendar, mackit-reminders, etc.)
```

## Adding a New Command

1. Add method to service protocol in `Sources/MacKitCore/Services/`
2. Implement in `Live*Service` (real Apple framework calls)
3. Add to `Mock*Service` in `Tests/MacKitCoreTests/Mocks/`
4. Write tests using mock
5. Create command in `Sources/mackit/Commands/`
6. Register in parent command's `subcommands` array
7. Add MCP tool definition in `MCPTools.swift` + handler in `MCPServer.swift`
8. Update skill SKILL.md

## Adding a New Data Domain

1. Create model in `Sources/MacKitCore/Models/` (conform to `Codable`, `Sendable`, `TextRepresentable`, `TableRepresentable`, `FieldSelectable`)
2. Create service protocol + Live implementation in `Services/`
3. Create mock in `Tests/Mocks/`
4. Create command file in `Sources/mackit/Commands/`
5. Register in `MacKit.swift` subcommands
6. Add MCP tools in `MCPTools.swift` + handlers in `MCPServer.swift`
7. Create skill in `skills/mackit-<domain>/SKILL.md`

## Conventions

- **Error handling**: Use `MacKitError` cases. Permission errors must include System Settings path.
- **Destructive operations**: Require `--yes` flag, show preview without it.
- **Date input**: Support ISO 8601, natural language (today, tomorrow, monday), time (3pm, 14:30).
- **Output**: Every command supports `--format json|text|table` and `--json FIELDS`.
- **Testing**: Swift Testing framework (`@Suite`, `@Test`, `#expect`). No XCTest.
- **Commit style**: Conventional commits (`feat:`, `fix:`, `test:`, `docs:`).

## TCC Permissions

Calendar and Contacts permissions work from most terminals. Reminders has a known issue where Warp.app doesn't trigger the TCC dialog. Users need to run `mackit rem lists` from Terminal.app first, or manually grant in System Settings.

## MCP Server

`mackit mcp` runs a JSON-RPC stdio server. Test with:
```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | mackit mcp
```
