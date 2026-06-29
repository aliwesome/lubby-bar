import Foundation

/// Runs when Claude Code invokes `LubbyBar hook <event>`. Reads the small JSON
/// payload Claude pipes on stdin (session id + cwd only) and records a coarse
/// status in ~/.lubby-bar/status.json. It deliberately never touches the
/// transcript, prompt, or any file contents.
enum HookCLI {
    static func run(event: String) {
        var sessionId = "default"
        var cwd: String?

        if let data = readStdin(),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let sid = obj["session_id"] as? String, !sid.isEmpty { sessionId = sid }
            if let dir = obj["cwd"] as? String, !dir.isEmpty { cwd = dir }
        }

        // Capture where this session lives so the bar can jump back to it: the
        // controlling terminal device and which terminal app it's running in.
        let tty = controllingTTY()
        let termProgram = ProcessInfo.processInfo.environment["TERM_PROGRAM"]

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

        StatusStore.upsert(
            session: sessionId, status: status, agent: "claude_code",
            cwd: cwd, tty: tty, termProgram: termProgram
        )
    }

    /// Read stdin to EOF, but never block on an interactive terminal.
    private static func readStdin() -> Data? {
        if isatty(FileHandle.standardInput.fileDescriptor) != 0 { return nil }
        return try? FileHandle.standardInput.readToEnd()
    }

    /// The controlling terminal of this hook process (shared with the Claude
    /// session that spawned it), e.g. "/dev/ttys004". Claude pipes JSON over
    /// stdin and may redirect stdout/stderr, so the reliable handle is /dev/tty.
    /// Returns nil if the hook has no controlling terminal.
    private static func controllingTTY() -> String? {
        // /dev/tty resolves to the process's controlling terminal regardless of
        // how the standard fds were redirected.
        let fd = open("/dev/tty", O_RDONLY | O_NOCTTY)
        if fd >= 0 {
            defer { close(fd) }
            if let name = ttyName(fd) { return name }
        }
        // Fall back to the standard descriptors in case one is still a tty.
        for candidate in [STDERR_FILENO, STDOUT_FILENO, STDIN_FILENO] {
            if isatty(candidate) != 0, let name = ttyName(candidate) { return name }
        }
        return nil
    }

    private static func ttyName(_ fd: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard ttyname_r(fd, &buffer, buffer.count) == 0 else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }
}
