import AppKit
import Combine
import SwiftUI

/// Measures the notch on a screen. Returns nil on screens without a notch
/// (external displays, non-notched MacBooks), which is how the island stays
/// MacBook-notch-only and the app falls back to the menu-bar item elsewhere.
struct NotchGeometry {
    let menuBarHeight: CGFloat
    let notchWidth: CGFloat
    /// Global (bottom-left origin) coordinates used to pin the window.
    let notchCenterX: CGFloat
    let screenTop: CGFloat

    init?(screen: NSScreen) {
        let inset = screen.safeAreaInsets.top
        guard inset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }

        let notch = right.minX - left.maxX
        guard notch > 0 else { return nil }

        menuBarHeight = inset
        notchWidth = notch
        notchCenterX = (left.maxX + right.minX) / 2
        screenTop = screen.frame.maxY
    }
}

/// Owns the always-on-top window that draws the Dynamic-Island-style pill around
/// the notch. The window is sized to exactly the visible pill and grows only when
/// the drawer opens, so it never covers (and never steals clicks from) anything
/// below the menu bar. Hover expands it; a click pins it open and a click
/// anywhere else dismisses it. Rebuilds when the screen layout changes.
@MainActor
final class NotchIsland {
    private let model: AppModel
    private let state = NotchState()
    private var geometry: NotchGeometry?
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var outsideClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    /// True when the main screen has a notch (the island is shown). Used by the
    /// app to hide the redundant menu-bar item on notched Macs.
    static var mainScreenHasNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return NotchGeometry(screen: screen) != nil
    }

    init(model: AppModel) {
        self.model = model

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        state.$pinned
            .sink { [weak self] pinned in self?.updateOutsideClickMonitor(pinned) }
            .store(in: &cancellables)
    }

    /// Build the window if the main screen has a notch. Safe to call repeatedly.
    func activate() {
        teardown()
        guard let screen = NSScreen.main,
              let geometry = NotchGeometry(screen: screen)
        else {
            model.notchActive = false
            return
        }
        self.geometry = geometry
        model.notchActive = true

        let view = NotchIslandView(
            model: model,
            state: state,
            menuBarHeight: geometry.menuBarHeight,
            notchWidth: geometry.notchWidth,
            onLayout: { [weak self] layout in self?.apply(layout) },
            onSettings: { [weak self] in self?.openSettings() }
        )

        let initial = NSRect(
            x: geometry.notchCenterX - (geometry.notchWidth + 184) / 2,
            y: geometry.screenTop - geometry.menuBarHeight,
            width: geometry.notchWidth + 184,
            height: geometry.menuBarHeight
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: initial.size)
        hosting.autoresizingMask = [.width, .height]

        let win = NSWindow(
            contentRect: initial,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        win.ignoresMouseEvents = false
        win.contentView = hosting
        win.orderFrontRegardless()

        window = win
    }

    /// Track the SwiftUI content layout so the window always hugs the
    /// pill/drawer and keeps the notch gap aligned with the physical notch (the
    /// ears can differ in width). Fires once per real change; the smooth
    /// grow/shrink is the AppKit window animation, which is cheap.
    private func apply(_ layout: IslandLayout) {
        guard let window, let geometry,
              layout.size.width > 0, layout.size.height > 0 else { return }
        let notchLeft = geometry.notchCenterX - geometry.notchWidth / 2
        let frame = NSRect(
            x: notchLeft - layout.leftEar,
            y: geometry.screenTop - layout.size.height,
            width: layout.size.width,
            height: layout.size.height
        )
        guard frame != window.frame else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.38
            // Strong, smooth deceleration (no overshoot) for a calm grow/shrink.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            window.animator().setFrame(frame, display: true)
        }
    }

    /// Open (or focus) a small window hosting the full settings panel. On notched
    /// Macs this is the only entry point to settings, since the menu-bar item is
    /// hidden in favor of the island.
    private func openSettings() {
        state.pinned = false
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(
            rootView: PanelView().environmentObject(model).frame(width: 320)
        )
        let win = NSWindow(contentViewController: host)
        win.title = "Lubby Bar"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateOutsideClickMonitor(_ pinned: Bool) {
        if pinned, outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                self?.state.pinned = false
            }
        } else if !pinned, let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    @objc private func screensChanged() {
        activate()
    }

    private func teardown() {
        state.pinned = false
        window?.orderOut(nil)
        window = nil
        geometry = nil
    }
}
