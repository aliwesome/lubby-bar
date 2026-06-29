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

    /// How the collapsed notch indicator renders the live sessions.
    enum IndicatorStyle: String, CaseIterable {
        case aggregate  // one dot, rolled-up status
        case sessions   // one small dot per session
        case blend      // proportional gradient across the notch
    }

    @Published var sourceMode: SourceMode {
        didSet {
            defaults.set(sourceMode.rawValue, forKey: Keys.sourceMode)
            restartSource()
        }
    }

    @Published var serverURL: String {
        didSet {
            defaults.set(serverURL, forKey: Keys.serverURL)
            restartFeed()
        }
    }

    @Published var indicatorStyle: IndicatorStyle {
        didSet { defaults.set(indicatorStyle.rawValue, forKey: Keys.indicatorStyle) }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var sessions: [SessionInfo] = []
    @Published private(set) var loggedIn: Bool
    @Published var connectionError: String?

    // Set by the notch island once it knows whether the main screen has a notch.
    // Drives hiding the redundant menu-bar item on notched Macs. Set late (in
    // applicationDidFinishLaunching) because the notch geometry isn't ready at
    // App init time.
    @Published var notchActive = false

    // Login ceremony state, surfaced in the panel.
    @Published var loginUserCode: String?
    @Published var loginInProgress = false

    @Published var hookInstalled = false
    @Published var launchAtLogin = false

    private let defaults = UserDefaults.standard
    private let local = LocalSource()
    private let lubby = LubbySource()
    private let feed = PresenceFeed()

    // Social/presence layer (Lubby mode only).
    @Published private(set) var nearby: NearbySummary?
    @Published private(set) var alerts: [Alert] = []
    @Published private(set) var connections: [Person] = []
    @Published private(set) var nearbyPeople: [Person] = []
    /// Set to the most recent genuinely-new alert so the notch can pop a toast.
    @Published var latestToast: Alert?
    private var seenAlertIDs: Set<Int> = []

    private enum Keys {
        static let sourceMode = "sourceMode"
        static let serverURL = "serverURL"
        static let indicatorStyle = "indicatorStyle"
    }

    private init() {
        sourceMode = SourceMode(rawValue: defaults.string(forKey: Keys.sourceMode) ?? "") ?? .local
        serverURL = defaults.string(forKey: Keys.serverURL) ?? "https://lubby.tech"
        indicatorStyle = IndicatorStyle(rawValue: defaults.string(forKey: Keys.indicatorStyle) ?? "") ?? .aggregate
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
        feed.onNearby = { [weak self] summary in self?.nearby = summary }
        feed.onAlerts = { [weak self] alerts in self?.ingest(alerts: alerts) }
        feed.onPeople = { [weak self] connections, nearby in
            self?.connections = connections
            self?.nearbyPeople = nearby
        }

        refreshHookState()
        refreshLaunchAtLogin()
        restartSource()
        restartFeed()
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

    /// The social/presence layer (Lubby page) runs whenever the machine is
    /// connected to Lubby (has a token), independent of which status source is
    /// chosen, so Local-mode users still get presence and pings.
    func restartFeed() {
        feed.stop()
        seenAlertIDs.removeAll()
        nearby = nil
        alerts = []
        connections = []
        nearbyPeople = []
        guard let token = Keychain.get(), !token.isEmpty else { return }
        feed.serverURL = serverURL
        feed.token = token
        feed.start()
    }

    /// Replace the alert list and pop a toast for the newest genuinely-new alert.
    /// On the first poll we don't pop the whole backlog, but we still toast
    /// anything unread from the last few minutes, so a hi sent moments before you
    /// connected still notifies.
    private func ingest(alerts: [Alert]) {
        let firstPoll = seenAlertIDs.isEmpty && self.alerts.isEmpty
        let recentCutoff = Date().addingTimeInterval(-3 * 60)
        let fresh = alerts.filter { alert in
            guard alert.unread, !seenAlertIDs.contains(alert.id) else { return false }
            if firstPoll {
                guard let created = alert.createdAt, created > recentCutoff else { return false }
            }
            return true
        }
        alerts.forEach { seenAlertIDs.insert($0.id) }
        self.alerts = alerts
        if let toast = fresh.first {
            latestToast = toast
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
        restartFeed()
    }

    func disconnect() {
        Keychain.delete()
        loggedIn = false
        if sourceMode == .lubby { restartSource() }
        restartFeed()
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
        open(path: "")
    }

    func openMap() {
        open(path: "/map")
    }

    func open(path: String) {
        if let url = URL(string: serverURL.trimmedSlash + path) {
            NSWorkspace.shared.open(url)
        }
    }

}
