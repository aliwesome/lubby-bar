import AppKit
import Combine
import Foundation
import ServiceManagement

/// Owns the current status, the chosen source, and the user-facing settings.
/// SwiftUI observes it; all @Published mutations happen on the main thread.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum SourceMode: String {
        case local
        case lubby
    }

    @Published var sourceMode: SourceMode {
        didSet {
            defaults.set(sourceMode.rawValue, forKey: Keys.sourceMode)
            restartSource()
        }
    }

    @Published var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Keys.serverURL) }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var sessions: [SessionInfo] = []
    @Published private(set) var loggedIn: Bool
    @Published var connectionError: String?

    // Login ceremony state, surfaced in the panel.
    @Published var loginUserCode: String?
    @Published var loginInProgress = false

    @Published var hookInstalled = false
    @Published var launchAtLogin = false

    private let defaults = UserDefaults.standard
    private let local = LocalSource()
    private let lubby = LubbySource()

    private enum Keys {
        static let sourceMode = "sourceMode"
        static let serverURL = "serverURL"
    }

    private init() {
        sourceMode = SourceMode(rawValue: defaults.string(forKey: Keys.sourceMode) ?? "") ?? .local
        serverURL = defaults.string(forKey: Keys.serverURL) ?? "https://lubby.tech"
        loggedIn = Keychain.get() != nil

        local.onUpdate = { [weak self] infos in
            self?.apply(sessions: infos, overall: aggregate(infos.map(\.status)))
        }
        lubby.onUpdate = { [weak self] infos, overall in
            self?.connectionError = nil
            self?.apply(sessions: infos, overall: overall)
        }
        lubby.onError = { [weak self] message in
            self?.connectionError = message
        }

        refreshHookState()
        refreshLaunchAtLogin()
        restartSource()
    }

    private func apply(sessions: [SessionInfo], overall: Status) {
        self.sessions = sessions
        status = overall
    }

    // MARK: - Source switching

    func restartSource() {
        local.stop()
        lubby.stop()
        connectionError = nil

        switch sourceMode {
        case .local:
            local.start()
        case .lubby:
            guard let token = Keychain.get(), !token.isEmpty else {
                apply(sessions: [], overall: .idle)
                return
            }
            lubby.serverURL = serverURL
            lubby.token = token
            lubby.start()
        }
    }

    // MARK: - Local hook

    func refreshHookState() {
        hookInstalled = HookInstaller.isInstalled()
    }

    func installHook() {
        do {
            try HookInstaller.install()
        } catch {
            connectionError = "Could not write Claude settings: \(error.localizedDescription)"
        }
        refreshHookState()
    }

    func uninstallHook() {
        try? HookInstaller.uninstall()
        refreshHookState()
    }

    // MARK: - Lubby login

    func connect() {
        guard !loginInProgress else { return }
        loginInProgress = true
        loginUserCode = nil
        connectionError = nil

        let login = DeviceLogin(serverURL: serverURL)
        Task {
            do {
                let start = try await login.start(clientName: "Lubby Bar (macOS)")
                await MainActor.run {
                    self.loginUserCode = start.user_code
                    if let url = URL(string: start.verification_uri_complete) {
                        NSWorkspace.shared.open(url)
                    }
                }
                let token = try await login.poll(
                    claimToken: start.claim_token, interval: start.interval, expiresIn: start.expires_in
                )
                await MainActor.run { self.finishLogin(token: token) }
            } catch {
                await MainActor.run {
                    self.loginInProgress = false
                    self.loginUserCode = nil
                    self.connectionError = error.localizedDescription
                }
            }
        }
    }

    func saveManualToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        finishLogin(token: trimmed)
    }

    private func finishLogin(token: String) {
        Keychain.set(token)
        loggedIn = true
        loginInProgress = false
        loginUserCode = nil
        if sourceMode == .lubby { restartSource() }
    }

    func disconnect() {
        Keychain.delete()
        loggedIn = false
        if sourceMode == .lubby { restartSource() }
    }

    // MARK: - Launch at login

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            connectionError = "Launch at login failed: \(error.localizedDescription)"
        }
        refreshLaunchAtLogin()
    }

    func openServer() {
        if let url = URL(string: serverURL.trimmedSlash) {
            NSWorkspace.shared.open(url)
        }
    }
}
