# mackit Development Guide

## Project

Native macOS CLI tool for accessing calendar, reminders, contacts, mail, focus status, and notifications. Includes MCP server for AI agent integration.

**Binary:** `mackit` | **Package:** `macos-kit` | **Language:** Swift 6.0 | **Min OS:** macOS 13

## Architecture

Three-target design:
- `MacKitCore` (library): services, models, output rendering, MCP server. All Apple framework calls behind protocols for testability.
- `mackit` (executable): thin CLI wrapper using swift-argument-parser.
- `MacKitHost` (app executable): owns macOS permissions and executes hosted CLI/MCP requests over private local IPC.

Key patterns:
- **Protocol-based services**: `CalendarServiceProtocol` + `LiveCalendarService` + `MockCalendarService`
- **EventKitMapper**: Shared mapping from EKEvent to CalendarEvent, used by both read and write services
- **FreeSlotCalculator**: Shared free time slot logic used by CLI and MCP server
- **Sendable models**: Map non-Sendable Apple types (EKReminder, CNContact) to Sendable structs inside closures before crossing async boundaries
- **`@preconcurrency import EventKit`**: Required for reminder fetch callbacks in Swift 6
- **Output auto-detection**: `isatty(STDOUT_FILENO)` chooses text vs JSON
- **FieldSelectable protocol**: Static `availableFields` list for `--json` field validation (avoids optional-nil-key problem)
- **MCP server reuses services**: Single instance per service type, not per tool call
- **Bounded host execution**: Hosted commands have deadlines, concurrency/output caps, disconnect cancellation, a single-instance lock, and metadata-only JSONL logs
- **Paged mail queries**: List/search use `MailQuery` + `MailPage`; expensive recipients, bodies, and attachments are opt-in

## Build & Test

```bash
swift build              # Debug build
swift build -c release   # Release build
swift test               # Unit tests need no TCC permissions
scripts/install-mackit.sh # Build and install MacKit.app plus the CLI
mackit --version         # Verify installed binary
mackit doctor            # Verify app installation, host socket, and log path

# Shell completions
mackit completions zsh > ~/.zfunc/_mackit
mackit completions bash > /usr/local/etc/bash_completion.d/mackit
mackit completions fish > ~/.config/fish/completions/mackit.fish
```

Unit tests use mocks exclusively. No calendar/contacts/reminders/mail access is
needed in CI. Live CLI and MCP integration tests run through the installed
`MacKit.app`, which owns the stable TCC identity and communicates with the CLI
over a mode-600 Unix socket in `~/Library/Application Support/MacKit`.

## Directory Structure

```
Sources/mackit/Commands/        # CLI commands (one file per domain + write commands)
Sources/MacKitHost/             # Permission-owning local host app
Sources/MacKitCore/Host/        # Host IPC protocol and routing
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

`MacKit.app` owns Calendar, Reminders, Contacts, Apple Events, and notification
permissions. The CLI and MCP server must route permission-sensitive work through
the host so permissions do not depend on Terminal, Warp, Codex, or another parent.

## MCP Server

`mackit mcp` runs a JSON-RPC stdio server. Test with:
```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | mackit mcp
```
