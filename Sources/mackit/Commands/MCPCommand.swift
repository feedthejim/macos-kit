import ArgumentParser
import MacKitCore

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Start MCP server (stdio transport)"
    )

    func run() async throws {
        let server = MCPServer()
        try await server.run()
    }
}
