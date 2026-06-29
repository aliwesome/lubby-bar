import Foundation

/// Idempotently wires the `LubbyBar hook` subcommand into Claude Code's
/// ~/.claude/settings.json. Mirrors the connector's approach: preserve every
/// existing hook, only add/replace our own. Detects our entries by the binary
/// name plus the " hook " marker, so reinstalling updates a moved app path.
enum HookInstaller {
    // SessionStart/UserPromptSubmit/PreToolUse all mean "the agent is working"
    // (green). Without UserPromptSubmit + PreToolUse the dot would stick on the
    // last Stop and never return to green when a new turn begins.
    private static let events: [(claudeEvent: String, arg: String)] = [
        ("SessionStart", "started"),
        ("UserPromptSubmit", "started"),
        ("PreToolUse", "started"),
        ("Notification", "waiting_input"),
        ("Stop", "completed"),
    ]

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static func command(for arg: String) -> String {
        let binary = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return "\"\(binary)\" hook \(arg)"
    }

    static func isInstalled() -> Bool {
        guard let root = readSettings(), let hooks = root["hooks"] as? [String: Any] else { return false }
        for (event, arg) in events {
            let groups = hooks[event] as? [[String: Any]] ?? []
            let found = groups.contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { isOurs($0, arg: arg) }
            }
            if !found { return false }
        }
        return true
    }

    static func install() throws {
        var root = readSettings() ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for (event, arg) in events {
            var groups = stripOurs(from: hooks[event] as? [[String: Any]] ?? [])
            groups.append(["hooks": [["type": "command", "command": command(for: arg)]]])
            hooks[event] = groups
        }

        root["hooks"] = hooks
        try writeSettings(root)
    }

    static func uninstall() throws {
        guard var root = readSettings(), var hooks = root["hooks"] as? [String: Any] else { return }

        for (event, _) in events {
            let groups = stripOurs(from: hooks[event] as? [[String: Any]] ?? [])
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }

        root["hooks"] = hooks
        try writeSettings(root)
    }

    // MARK: - Helpers

    /// Remove our hook entries from a list of groups, dropping any group left empty.
    private static func stripOurs(from groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group in
            var updated = group
            var inner = group["hooks"] as? [[String: Any]] ?? []
            inner.removeAll { isOurs($0, arg: nil) }
            if inner.isEmpty { return nil }
            updated["hooks"] = inner
            return updated
        }
    }

    private static func isOurs(_ hook: [String: Any], arg: String?) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        guard command.contains("LubbyBar"), command.contains(" hook ") else { return false }
        if let arg { return command.contains("hook \(arg)") }
        return true
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private static func writeSettings(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }
}
