import Foundation

/// On-disk shape of ~/.lubby-bar/status.json, written by the `hook` subcommand
/// and read by LocalSource. Keyed by Claude session id so concurrent sessions
/// each get a row. Stays on the machine, never sent anywhere in local mode.
struct LocalStatusFile: Codable {
    var sessions: [String: LocalSession]
}

struct LocalSession: Codable {
    var status: String
    var agent: String
    var project: String?
    var updated_at: String
    /// Absolute cwd, controlling tty, and terminal app, captured by the hook so
    /// the bar can jump to the exact terminal. Optional for backward compat with
    /// status files written by older builds.
    var cwd: String?
    var tty: String?
    var term_program: String?
}

enum StatusStore {
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lubby-bar", isDirectory: true)
    }

    static var fileURL: URL { dir.appendingPathComponent("status.json") }

    static func read() -> LocalStatusFile? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(LocalStatusFile.self, from: data)
    }

    static func write(_ file: LocalStatusFile) {
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func upsert(
        session: String, status: String, agent: String,
        cwd: String? = nil, tty: String? = nil, termProgram: String? = nil
    ) {
        var file = read() ?? LocalStatusFile(sessions: [:])
        let formatter = ISO8601DateFormatter()
        // Preserve location fields across events: a later "stop" hook may not be
        // able to read the tty (terminal already gone), so keep what we first saw.
        let existing = file.sessions[session]
        // Resolve the project label once, when the session first appears: the git
        // repo's folder name (so a subdir like .../istanbul-nomads/laravel reads
        // "istanbul-nomads"), falling back to the cwd's own folder name.
        let project = existing?.project ?? projectName(cwd: cwd)

        file.sessions[session] = LocalSession(
            status: status, agent: agent, project: project,
            updated_at: formatter.string(from: Date()),
            cwd: cwd ?? existing?.cwd,
            tty: tty ?? existing?.tty,
            term_program: termProgram ?? existing?.term_program
        )

        // Prune abandoned sessions: anything not updated within the window is
        // treated as gone (a closed terminal never fires Stop). Keeps the file
        // and the panel to what's actually live.
        let cutoff = Date().addingTimeInterval(-30 * 60)
        file.sessions = file.sessions.filter { _, s in
            guard let updated = formatter.date(from: s.updated_at) else { return false }
            return updated > cutoff
        }
        write(file)
    }

    /// A readable, distinguishable project label. At a git repo root it's the
    /// repo folder name ("lubby"); inside a subdir it's "repo/leaf"
    /// ("lubby/web") so sibling subdirs of the same repo don't collide; outside a
    /// repo it's just the cwd's folder name. Runs git only here (once per new
    /// session in upsert), not on every hook event.
    private static func projectName(cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let leaf = URL(fileURLWithPath: cwd).lastPathComponent
        guard let root = gitRoot(cwd: cwd) else { return leaf }

        let repo = URL(fileURLWithPath: root).lastPathComponent
        let atRoot = URL(fileURLWithPath: root).standardizedFileURL.path
            == URL(fileURLWithPath: cwd).standardizedFileURL.path
        return atRoot ? repo : "\(repo)/\(leaf)"
    }

    private static func gitRoot(cwd: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", cwd, "rev-parse", "--show-toplevel"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }
}
