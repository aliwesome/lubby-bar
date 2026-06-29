import Foundation

/// Aggregate "who's waiting nearby right now" from GET /api/presence/waiting.
/// Counts only, never names or content.
struct NearbySummary: Equatable {
    var total: Int
    var topStack: String?
    var topStackCount: Int
}

/// A social alert from GET /api/me/notifications (someone said hi, a connection
/// request, etc.). Drives the panel feed and the notch toast.
struct Alert: Identifiable, Equatable {
    let id: Int
    let type: String
    let actorName: String?
    let url: String?
    let unread: Bool

    var actor: String { actorName?.isEmpty == false ? actorName! : "Someone" }

    var emoji: String {
        switch type {
        case "hi": return "👋"
        case "connection_request": return "🔗"
        case "connection_accepted": return "✅"
        default: return "🔔"
        }
    }

    var message: String {
        switch type {
        case "hi": return "\(actor) said hi"
        case "connection_request": return "\(actor) wants to connect"
        case "connection_accepted": return "\(actor) connected with you"
        default: return "New activity"
        }
    }
}

/// A person in the Lubby People list (a connection or a nearby waiting dev) from
/// GET /api/me/people. The timezone drives both their local time and a coarse
/// "City, Region" location label; never carries coordinates or private data.
struct Person: Identifiable, Equatable {
    let id: Int
    let name: String
    let username: String?
    let avatarURL: String?
    let timezone: String?
    let status: Status

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    /// "Asia/Tehran" -> "Tehran, Asia". Nil when no timezone is known.
    var placeLabel: String? {
        guard let timezone, timezone.contains("/") else { return nil }
        let parts = timezone.split(separator: "/")
        guard let region = parts.first, let city = parts.last else { return nil }
        let cityName = city.replacingOccurrences(of: "_", with: " ")
        return "\(cityName), \(region)"
    }
}

/// Polls the Lubby server (in Lubby mode) for the social/presence layer: nearby
/// waiting counts and recent alerts. Independent of the status source so the
/// status dot keeps updating even if the social endpoints are slow.
final class PresenceFeed {
    var onNearby: ((NearbySummary) -> Void)?
    var onAlerts: (([Alert]) -> Void)?
    var onPeople: (([Person], [Person]) -> Void)?

    var serverURL = ""
    var token = ""

    private var timer: Timer?

    func start() {
        stop()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        fetchNearby()
        fetchAlerts()
        fetchPeople()
    }

    private func request(path: String) -> URLRequest? {
        guard !token.isEmpty, let url = URL(string: serverURL.trimmedSlash + path) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: - Nearby

    private struct WaitingResponse: Codable {
        let total: Int
        let stacks: [Stack]
        struct Stack: Codable { let stack: String; let count: Int }
    }

    private func fetchNearby() {
        guard let request = request(path: "/api/presence/waiting") else { return }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let data,
                  let decoded = try? JSONDecoder().decode(WaitingResponse.self, from: data)
            else { return }

            let top = decoded.stacks.first
            let summary = NearbySummary(
                total: decoded.total,
                topStack: top?.stack,
                topStackCount: top?.count ?? 0
            )
            DispatchQueue.main.async { self.onNearby?(summary) }
        }.resume()
    }

    // MARK: - Alerts

    private struct AlertsResponse: Codable {
        let unread_count: Int
        let alerts: [Item]
        struct Item: Codable {
            let id: Int
            let type: String
            let actor_name: String?
            let url: String?
            let unread: Bool
        }
    }

    private func fetchAlerts() {
        guard let request = request(path: "/api/me/notifications") else { return }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let data,
                  let decoded = try? JSONDecoder().decode(AlertsResponse.self, from: data)
            else { return }

            let alerts = decoded.alerts.map {
                Alert(id: $0.id, type: $0.type, actorName: $0.actor_name, url: $0.url, unread: $0.unread)
            }
            DispatchQueue.main.async { self.onAlerts?(alerts) }
        }.resume()
    }

    // MARK: - People

    private struct PeopleResponse: Codable {
        let connections: [Item]
        let nearby: [Item]
        struct Item: Codable {
            let id: Int
            let name: String
            let username: String?
            let avatar_url: String?
            let timezone: String?
            let status: String
        }
    }

    private func fetchPeople() {
        guard let request = request(path: "/api/me/people") else { return }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let data,
                  let decoded = try? JSONDecoder().decode(PeopleResponse.self, from: data)
            else { return }

            let map: (PeopleResponse.Item) -> Person = {
                Person(
                    id: $0.id, name: $0.name, username: $0.username,
                    avatarURL: $0.avatar_url, timezone: $0.timezone,
                    status: Status.from(raw: $0.status)
                )
            }
            let connections = decoded.connections.map(map)
            let nearby = decoded.nearby.map(map)
            DispatchQueue.main.async { self.onPeople?(connections, nearby) }
        }.resume()
    }
}
