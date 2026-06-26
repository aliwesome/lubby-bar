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

        for (_, session) in file?.sessions ?? [:] {
            let updated = formatter.date(from: session.updated_at)
            var raw = session.status
            if raw == "running", let updated, now.timeIntervalSince(updated) > staleAfter {
                raw = "stopped"
            }
            infos.append(SessionInfo(
                agent: session.agent,
                status: Status.from(raw: raw),
                project: session.project,
                updatedAt: updated
            ))
        }

        infos.sort { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        onUpdate?(infos)
    }
}
