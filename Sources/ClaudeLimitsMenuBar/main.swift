import AppKit

// Entry point. This is a menu-bar-only ("accessory") app: no Dock icon, no main window.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = StatusController()
app.run()
