import SwiftUI

struct LubbyBarApp: App {
    @StateObject private var model = AppModel.shared

    init() {
        // Menu-bar utility: no Dock icon, no main window.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(model)
                .frame(width: 300)
        } label: {
            Image(nsImage: dotImage(model.status.nsColor))
        }
        .menuBarExtraStyle(.window)
    }
}
