import AppKit
import SwiftUI

/// Coarse status the widget renders. The request maps:
/// running -> green, waiting -> orange, stopped -> red. Idle is "nothing active".
enum Status: String {
    case running
    case waitingInput = "waiting_input"
    case stopped
    case idle

    /// Normalize any raw status string from the server or the local hook file.
    static func from(raw: String) -> Status {
        switch raw {
        case "running", "heartbeat", "started":
            return .running
        case "waiting_input", "notification":
            return .waitingInput
        case "completed", "failed", "cancelled", "stopped", "stop":
            return .stopped
        default:
            return .idle
        }
    }

    var label: String {
        switch self {
        case .running: return "Running"
        case .waitingInput: return "Waiting for input"
        case .stopped: return "Stopped"
        case .idle: return "Idle"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .running: return .systemGreen
        case .waitingInput: return .systemOrange
        case .stopped: return .systemRed
        case .idle: return .secondaryLabelColor
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

struct SessionInfo: Identifiable {
    let id = UUID()
    var agent: String
    var status: Status
    var project: String?
    var updatedAt: Date?
}

/// Roll up many sessions into one dot. Priority: waiting (needs you) beats
/// running beats stopped beats idle.
func aggregate(_ statuses: [Status]) -> Status {
    if statuses.contains(.waitingInput) { return .waitingInput }
    if statuses.contains(.running) { return .running }
    if statuses.contains(.stopped) { return .stopped }
    return .idle
}

/// A colored, non-template dot for the menu bar. Template images get forced to
/// monochrome by the system, so we draw an explicit color and mark it non-template.
func dotImage(_ color: NSColor, diameter: CGFloat = 13) -> NSImage {
    let size = NSSize(width: diameter, height: diameter)
    let image = NSImage(size: size)
    image.lockFocus()
    color.setFill()
    let inset: CGFloat = 1.5
    NSBezierPath(ovalIn: NSRect(x: inset, y: inset, width: diameter - inset * 2, height: diameter - inset * 2)).fill()
    image.unlockFocus()
    image.isTemplate = false
    return image
}

extension String {
    /// URL base without a trailing slash, so "/api/..." can be appended safely.
    var trimmedSlash: String {
        var s = trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
