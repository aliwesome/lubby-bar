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

    static func upsert(session: String, status: String, agent: String, project: String?) {
        var file = read() ?? LocalStatusFile(sessions: [:])
        let formatter = ISO8601DateFormatter()
        file.sessions[session] = LocalSession(
            status: status, agent: agent, project: project, updated_at: formatter.string(from: Date())
        )
        // Keep the file small: drop terminal sessions older than an hour.
        let cutoff = Date().addingTimeInterval(-3600)
        file.sessions = file.sessions.filter { _, s in
            if s.status == "running" || s.status == "waiting_input" { return true }
            guard let updated = formatter.date(from: s.updated_at) else { return true }
            return updated > cutoff
        }
        write(file)
    }
}
