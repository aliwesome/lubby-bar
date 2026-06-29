import Foundation

/// Watches the local status file written by the `hook` subcommand. Polls every
/// few seconds (a tiny local read) which also handles atomic file replaces and
/// applies a staleness guard: hooks are event-based with no heartbeat, so a
/// "running" row with no update for ~30 min is treated as stopped (covers a
/// Claude crash where no Stop hook fired).
final class LocalSource {
    var onUpdate: (([SessionInfo]) -> Void)?

    private var timer: Timer?
    private let staleAfter: TimeInterval = 30 * 60

    func start() {
        stop()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let file = StatusStore.read()
        let now = Date()
        let formatter = ISO8601DateFormatter()
        var infos: [SessionInfo] = []

        for (key, session) in file?.sessions ?? [:] {
            let updated = formatter.date(from: session.updated_at)
            // Drop abandoned sessions: an active Claude session updates often
            // (every prompt/tool call), so no update for a while means the
            // terminal closed or crashed without a Stop hook. Hiding them keeps
            // the list to what's actually live, instead of a pile of stale rows.
            if let updated, now.timeIntervalSince(updated) > staleAfter { continue }
            if updated == nil { continue }

            infos.append(SessionInfo(
                id: key,
                agent: session.agent,
                status: Status.from(raw: session.status),
                project: session.project,
                updatedAt: updated,
                cwd: session.cwd,
                tty: session.tty,
                termProgram: session.term_program
            ))
        }

        // Stable order by project (then id), so rows don't jump around as their
        // statuses and timestamps tick - sorting by recency was the churn.
        infos.sort {
            let a = ($0.project ?? "").lowercased()
            let b = ($1.project ?? "").lowercased()
            return a == b ? $0.id < $1.id : a < b
        }
        onUpdate?(infos)
    }
}
