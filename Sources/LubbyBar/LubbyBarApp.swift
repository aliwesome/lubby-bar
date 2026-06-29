import SwiftUI

/// Spins up the notch island after launch. SwiftUI's MenuBarExtra covers the
/// menu-bar item; the island is an AppKit window, so it lives here. On screens
/// without a notch the island simply never appears and the menu-bar item is the
/// only indicator.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchIsland?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchIsland(model: .shared)
        notch?.activate()
    }
}

struct LubbyBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    init() {
        // Menu-bar utility: no Dock icon, no main window.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    // On a notched Mac the island is the indicator, so the menu-bar item is
    // hidden to avoid a redundant second panel. `notchActive` is set once the
    // island activates (the notch isn't measurable yet at App init).
    private var menuBarInserted: Binding<Bool> {
        Binding(get: { !model.notchActive }, set: { _ in })
    }

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarInserted) {
            PanelView()
                .environmentObject(model)
                .frame(width: 300)
        } label: {
            Image(nsImage: dotImage(model.status.nsColor))
        }
        .menuBarExtraStyle(.window)
    }
}
