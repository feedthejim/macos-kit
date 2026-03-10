import ArgumentParser

struct CompletionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completions",
        abstract: "Generate shell completion scripts",
        discussion: """
            Generates completion scripts for your shell. Add to your shell config:

            ZSH:
              mackit completions zsh > ~/.zfunc/_mackit
              # Add to .zshrc: fpath=(~/.zfunc $fpath); autoload -Uz compinit; compinit

            BASH:
              mackit completions bash > /usr/local/etc/bash_completion.d/mackit

            FISH:
              mackit completions fish > ~/.config/fish/completions/mackit.fish
            """
    )

    @Argument(help: "Shell type: zsh, bash, or fish")
    var shell: String

    func run() throws {
        let shellType: CompletionShell
        switch shell.lowercased() {
        case "zsh": shellType = .zsh
        case "bash": shellType = .bash
        case "fish": shellType = .fish
        default:
            throw ValidationError("Unknown shell '\(shell)'. Use: zsh, bash, or fish")
        }
        let script = MacKit.completionScript(for: shellType)
        print(script)
    }
}
