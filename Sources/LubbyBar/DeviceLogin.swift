import Foundation

enum LoginError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(text) = self { return text }
        return nil
    }
}

/// Lubby's OAuth 2.0 Device Authorization Grant (RFC 8628). Start a ceremony,
/// send the user to the approval page, then poll until a `lub_` token is minted.
struct DeviceLogin {
    let serverURL: String

    struct StartResponse: Codable {
        let claim_token: String
        let user_code: String
        let verification_uri_complete: String
        let interval: Int
        let expires_in: Int
    }

    private struct ClaimResponse: Codable {
        let status: String?
        struct Credential: Codable { let token: String }
        let credential: Credential?
    }

    func start(clientName: String) async throws -> StartResponse {
        var request = URLRequest(url: api("/agent/identity"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_name": clientName])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 201 else {
            throw LoginError.message("Could not reach \(serverURL).")
        }
        return try JSONDecoder().decode(StartResponse.self, from: data)
    }

    /// Polls /claim until approved (returns the token), denied, or expired.
    func poll(claimToken: String, interval: Int, expiresIn: Int) async throws -> String {
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        let wait = UInt64(max(1, interval)) * 1_000_000_000

        while Date() < deadline {
            try await Task.sleep(nanoseconds: wait)

            var request = URLRequest(url: api("/agent/identity/claim"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["claim_token": claimToken])

            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let decoded = try? JSONDecoder().decode(ClaimResponse.self, from: data)

            switch code {
            case 200:
                if let token = decoded?.credential?.token { return token }
            case 202:
                continue // authorization pending
            case 400:
                throw LoginError.message(decoded?.status == "denied" ? "Request denied." : "Request expired.")
            case 410:
                throw LoginError.message("Already claimed. Start again.")
            default:
                throw LoginError.message("Unexpected response (\(code)).")
            }
        }
        throw LoginError.message("Timed out waiting for approval.")
    }

    private func api(_ path: String) -> URL {
        URL(string: serverURL.trimmedSlash + "/api" + path)!
    }
}
