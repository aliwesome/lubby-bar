import AppKit
import Foundation

/// Jumps to the terminal a Claude session is running in. When the hook captured
/// the controlling tty we can focus the exact tab in Terminal.app or iTerm2 via
/// AppleScript; otherwise we fall back to opening the session's folder in its
/// terminal app. All work runs off the main thread (osascript blocks).
enum TerminalFocus {
    static func reveal(_ session: SessionInfo) {
        let tty = session.tty
        let cwd = session.cwd
        let app = TerminalApp(termProgram: session.termProgram)

        DispatchQueue.global(qos: .userInitiated).async {
            // Try to focus the exact tab first.
            if let tty, app.supportsTTYFocus, focusTab(app: app, tty: tty) {
                return
            }
            // Fall back to opening the folder in whichever terminal we know about.
            if let cwd {
                openFolder(cwd, in: app)
            } else if let tty {
                // No cwd recorded (older session): at least raise the terminal.
                _ = focusTab(app: app, tty: tty) || activate(app)
            }
        }
    }

    // MARK: - Terminal apps

    private enum TerminalApp {
        case terminal
        case iterm
        case other(bundleName: String?)

        init(termProgram: String?) {
            switch termProgram {
            case "iTerm.app": self = .iterm
            case "Apple_Terminal": self = .terminal
            case "vscode": self = .other(bundleName: "Visual Studio Code")
            case "Hyper": self = .other(bundleName: "Hyper")
            case "WarpTerminal": self = .other(bundleName: "Warp")
            case "ghostty": self = .other(bundleName: "Ghostty")
            case let other?: self = .other(bundleName: other)
            case nil: self = .terminal
            }
        }

        /// Only Terminal.app and iTerm2 expose per-tab tty over AppleScript.
        var supportsTTYFocus: Bool {
            switch self {
            case .terminal, .iterm: return true
            case .other: return false
            }
        }

        /// App name to hand to `open -a` for the folder fallback.
        var openName: String {
            switch self {
            case .terminal: return "Terminal"
            case .iterm: return "iTerm"
            case .other(let name): return name ?? "Terminal"
            }
        }
    }

    // MARK: - Exact-tab focus via AppleScript

    private static func focusTab(app: TerminalApp, tty: String) -> Bool {
        let script: String
        switch app {
        case .iterm:
            script = """
            tell application "iTerm"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(tty)" then
                      tell w to select t
                      select s
                      activate
                      tell w to set index to 1
                      return "found"
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            return "missing"
            """
        case .terminal:
            script = """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected tab of w to t
                    set frontmost of w to true
                    activate
                    return "found"
                  end if
                end repeat
              end repeat
            end tell
            return "missing"
            """
        case .other:
            return false
        }
        return runOSAScript(script) == "found"
    }

    // MARK: - Folder fallback

    private static func openFolder(_ path: String, in app: TerminalApp) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", app.openName, path]
        do {
            try proc.run()
        } catch {
            // Last resort: hand the folder to whatever the user set as default.
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    private static func activate(_ app: TerminalApp) -> Bool {
        runOSAScript("tell application \"\(app.openName)\" to activate") != nil
    }

    // MARK: - osascript runner

    /// Runs an AppleScript and returns its trimmed stdout, or nil on failure.
    /// Note: the first run triggers a one-time macOS automation permission prompt
    /// for controlling the terminal app.
    @discardableResult
    private static func runOSAScript(_ source: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
