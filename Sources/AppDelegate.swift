import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?
    private var hotkey: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("notchtray: launching")
        let controller = StatusBarController()
        self.controller = controller
        let hotkey = HotkeyManager { [weak controller] in controller?.toggle() }
        self.hotkey = hotkey
        controller.hotkeyAvailable = hotkey.isRegistered
    }

    // 收起状态下退出会把所有图标留在屏幕外，退出前必须还原
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.expandForQuit()
        return .terminateNow
    }
}
