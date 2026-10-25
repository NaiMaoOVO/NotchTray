import AppKit

// NotchTray —— 刘海收纳盘：把被刘海挡住/挤掉的状态栏图标收进一个下拉面板。
// LSUIElement 应用：不占 Dock，只活在菜单栏。
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
