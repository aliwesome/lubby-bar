import SwiftUI

/// The dropdown shown from the menu-bar icon: current status, the per-session
/// list, and an inline settings section (source picker, local hook, Lubby login,
/// launch at login). Kept in one panel so it works the same on macOS 13+.
struct PanelView: View {
    @EnvironmentObject var model: AppModel
    @State private var showSettings = false
    @State private var manualToken = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let error = model.connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            sessionList

            Divider()

            DisclosureGroup("Settings", isExpanded: $showSettings) {
                settings.padding(.top, 6)
            }
            .font(.subheadline.weight(.semibold))

            Divider()

            HStack {
                Button("Open Lubby") { model.openServer() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .font(.callout)
        }
        .padding(14)
        .onAppear {
            model.refreshHookState()
            model.refreshLaunchAtLogin()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.status.color)
                .frame(width: 11, height: 11)
            Text(model.status.label)
                .font(.headline)
            Spacer()
            if model.loggedIn {
                Text("Lubby")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        if model.sessions.isEmpty {
            Text("No active Claude sessions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.sessions) { session in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(session.status.color)
                            .frame(width: 8, height: 8)
                        Text(session.project ?? session.agent)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Text(session.status.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notch indicator")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Notch indicator", selection: indicatorBinding) {
                    Text("Dot").tag(AppModel.IndicatorStyle.aggregate)
                    Text("Per session").tag(AppModel.IndicatorStyle.sessions)
                    Text("Blend").tag(AppModel.IndicatorStyle.blend)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Sessions are always read from this device's Claude hook.
            localSettings

            Divider()

            // Connecting to Lubby only powers the social layer (presence, people, pings).
            lubbySettings

            Toggle("Launch at login", isOn: launchBinding)
                .font(.callout)
        }
    }

    @ViewBuilder
    private var localSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.hookInstalled
                 ? "Claude hook installed."
                 : "Install a Claude Code hook to detect status locally.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(model.hookInstalled ? "Reinstall hook" : "Install hook") {
                    model.installHook()
                }
                if model.hookInstalled {
                    Button("Remove") { model.uninstallHook() }
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private var lubbySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Server URL", text: $model.serverURL)
                .textFieldStyle(.roundedBorder)
                .font(.callout)

            if model.loggedIn {
                HStack {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Spacer()
                    Button("Disconnect") { model.disconnect() }
                        .font(.callout)
                }
            } else if model.loginInProgress {
                VStack(alignment: .leading, spacing: 4) {
                    if let code = model.loginUserCode {
                        Text("Approve in your browser. Code: \(code)")
                            .font(.caption)
                    } else {
                        Text("Starting…").font(.caption)
                    }
                    ProgressView().controlSize(.small)
                }
            } else {
                Button("Connect to Lubby") { model.connect() }
                    .font(.callout)

                DisclosureGroup("Paste a token instead") {
                    HStack {
                        SecureField("lub_…", text: $manualToken)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            model.saveManualToken(manualToken)
                            manualToken = ""
                        }
                    }
                    .font(.callout)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Bindings that route through the model's side effects.

    private var indicatorBinding: Binding<AppModel.IndicatorStyle> {
        Binding(get: { model.indicatorStyle }, set: { model.indicatorStyle = $0 })
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
    }
}
