import ArgumentParser
import MacKitCore

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Start MCP server (stdio transport)",
        discussion: """
            Runs a Model Context Protocol server that exposes mackit functionality \
            as tools for AI agents (Claude Code, Claude Desktop, etc.).

            The server reads JSON-RPC messages from stdin and writes responses to \
            stdout. It exposes 19 tools covering calendar, reminders, contacts, \
            focus status, and notifications.

            SETUP (Claude Code .mcp.json):
              { "mcpServers": { "mackit": { "command": "mackit", "args": ["mcp"] } } }

            SETUP (Claude Desktop):
              Add to ~/Library/Application Support/Claude/claude_desktop_config.json

            TEST:
              echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | mackit mcp
            """
    )

    func run() async throws {
        let server = MCPServer()
        try await server.run()
    }
}
