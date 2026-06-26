import Foundation

/// Polls a Lubby server's GET /api/me/sessions with the connector token and
/// reports the user's own status. The server already computes `overall`, so the
/// widget needs no business logic here.
final class LubbySource {
    var onUpdate: (([SessionInfo], Status) -> Void)?
    var onError: ((String) -> Void)?

    var serverURL = ""
    var token = ""

    private var timer: Timer?

    private struct Response: Codable {
        let overall: String
        let sessions: [Item]
        struct Item: Codable {
            let agent: String
            let status: String
            let stack: String?
        }
    }

    func start() {
        stop()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !token.isEmpty,
              let url = URL(string: serverURL.trimmedSlash + "/api/me/sessions") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                self.report(error: error.localizedDescription)
                return
            }

            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 {
                self.report(error: "Not authorized. Reconnect in settings.")
                return
            }
            guard code == 200, let data,
                  let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                self.report(error: "Server returned \(code).")
                return
            }

            let infos = decoded.sessions.map {
                SessionInfo(agent: $0.agent, status: Status.from(raw: $0.status), project: $0.stack, updatedAt: nil)
            }
            DispatchQueue.main.async {
                self.onUpdate?(infos, Status.from(raw: decoded.overall))
            }
        }.resume()
    }

    private func report(error: String) {
        DispatchQueue.main.async { self.onError?(error) }
    }
}
