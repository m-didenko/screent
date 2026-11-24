import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.accessory) // лише значок у рядку меню, без Dock
    withExtendedLifetime(controller) { app.run() }
}
