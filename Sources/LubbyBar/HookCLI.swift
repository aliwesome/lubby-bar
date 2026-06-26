import Foundation

/// Runs when Claude Code invokes `LubbyBar hook <event>`. Reads the small JSON
/// payload Claude pipes on stdin (session id + cwd only) and records a coarse
/// status in ~/.lubby-bar/status.json. It deliberately never touches the
/// transcript, prompt, or any file contents.
enum HookCLI {
    static func run(event: String) {
        var sessionId = "default"
        var project: String?

        if let data = readStdin(),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let sid = obj["session_id"] as? String, !sid.isEmpty { sessionId = sid }
            if let cwd = obj["cwd"] as? String, !cwd.isEmpty {
                project = URL(fileURLWithPath: cwd).lastPathComponent
            }
        }

        let status: String
        switch event {
        case "started", "running", "heartbeat":
            status = "running"
        case "waiting_input", "notification":
            status = "waiting_input"
        case "completed", "stop", "stopped", "end":
            status = "completed"
        default:
            status = "running"
        }

        StatusStore.upsert(session: sessionId, status: status, agent: "claude_code", project: project)
    }

    /// Read stdin to EOF, but never block on an interactive terminal.
    private static func readStdin() -> Data? {
        if isatty(FileHandle.standardInput.fileDescriptor) != 0 { return nil }
        return try? FileHandle.standardInput.readToEnd()
    }
}
