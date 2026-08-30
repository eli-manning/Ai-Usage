import Foundation

/// The one provider table.
///
/// In the split codebase this existed three times — `Provider.swift` in the
/// notch app, `OTHER_PROVIDERS` + `PROVIDER_COLORS` + `PROVIDER_LETTERS` +
/// `PROVIDER_LOGIN_CMD` in `main.js`, and a `PROVIDERS` array duplicated
/// across `popup.html`, `settings.html` and `wizard.html` — and it had already
/// drifted: install commands only ever existed on the Swift side, which is why
/// the tray app could tell you a CLI was missing but never offer to install it.
///
/// Brand colours are kept as hex strings here rather than SwiftUI `Color`s so
/// this file stays free of UI imports and testable in isolation; the app layer
/// converts them.
public struct Provider: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// Brand colour, as `RRGGBB`.
    public let colorHex: String
    /// The binary `which` should look for.
    public let binary: String
    /// Single letter for the tray badge when there's no percentage to show.
    public let letter: String
    /// Shown when the CLI isn't installed or isn't signed in.
    public let hint: String

    /// What "not installed" runs in a real Terminal window, for CLIs
    /// installable with a single package-manager command — preferred over
    /// `installURL` when both are set, since it actually installs the thing
    /// instead of handing the user a docs page to act on themselves.
    public let installCommand: String?
    /// Where "not installed" sends the user when there's no one-line
    /// `installCommand` — the CLI's own install page.
    public let installURL: String?
    /// What "installed, not signed in" runs in a real Terminal window. These
    /// CLIs' auth flows are interactive, so a background process can't drive
    /// them; the tap has to hand off to an actual terminal.
    public let loginCommand: String?

    /// Order matters — it's the tab order, and the fallback order used
    /// whenever the selected provider turns out to be disabled.
    public static let all: [Provider] = [
        Provider(
            id: "claude", name: "Claude", colorHex: "CC785C", binary: "claude", letter: "C",
            hint: "Run `claude` and follow the sign-in prompt.",
            installCommand: "npm install -g @anthropic-ai/claude-code",
            installURL: "https://docs.anthropic.com/en/docs/claude-code/setup",
            loginCommand: "claude"),

        Provider(
            id: "antigravity", name: "Antigravity", colorHex: "4E8CFF", binary: "agy", letter: "A",
            hint: "Run `agy`, then sign in with Google.",
            installCommand: "brew install --cask antigravity-cli",
            installURL: nil,
            loginCommand: "agy"),

        Provider(
            id: "codex", name: "Codex", colorHex: "3ECF8E", binary: "codex", letter: "X",
            hint: "Run `codex`, then `/status` for usage.",
            installCommand: "npm i -g @openai/codex",
            installURL: nil,
            loginCommand: "codex"),

        // The installer drops the binary in ~/.local/bin but — per its own
        // printed "Next Steps" — never adds that to PATH itself; it just tells
        // the user to append the export line by hand. Chaining that append onto
        // the install command (idempotent via `grep -qxF`, so reinstalling
        // never duplicates the line) is what makes "Install" actually leave you
        // with a working `cursor-agent`, rather than one that only works after
        // a manual PATH fix.
        Provider(
            id: "cursor", name: "Cursor", colorHex: "8B7CF6", binary: "cursor-agent", letter: "U",
            hint: "Run `cursor-agent`, then `/usage` for usage.",
            installCommand: #"curl -fsSL https://cursor.com/install | bash && (grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' ~/.zshrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc)"#,
            installURL: nil,
            loginCommand: "cursor-agent login"),
    ]

    public static func byID(_ id: String) -> Provider? {
        all.first { $0.id == id }
    }

    public static var ids: [String] { all.map(\.id) }
}
