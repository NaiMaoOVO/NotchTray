// 给（屏幕外的）状态图标窗口截图，用于在收纳面板里显示。
// 基于 menubar-hide (github.com/junior-rj/menubar-hide, MIT) 的实现改编，见 README 致谢。
// 优先走 CGWindowList 旧接口，失败再退回 ScreenCaptureKit；两者都需要"屏幕录制"权限。

import AppKit
import ScreenCaptureKit

@MainActor
enum ItemCapturer {
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// 窗口所在屏幕的缩放系数。NSScreen.frame 与 CGWindowList 坐标系 Y 轴相反，
    /// 但 X 一致，而状态图标按 X 就能唯一确定所在屏幕。
    private static func scale(for frame: CGRect) -> CGFloat {
        let midX = frame.midX
        let screen = NSScreen.screens.first { $0.frame.minX <= midX && midX < $0.frame.maxX }
        return (screen ?? NSScreen.main)?.backingScaleFactor ?? 2
    }

    static func capture(_ windows: [MenuBarItemWindow]) async -> [CapturedItem] {
        NSLog("notchtray: capturing \(windows.count) windows")

        var content: SCShareableContent?
        var triedFetchingContent = false

        var items: [CapturedItem] = []
        for window in windows {
            // 旧接口优先：小窗口更省。屏幕外的窗口两个接口都截不到（SCK 报 -3811、旧接口返回 nil），
            // 这正是 openPanel 里"闪现展开再截"重试存在的原因
            if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow,
                                                     window.id, [.boundsIgnoreFraming, .bestResolution]) {
                items.append(CapturedItem(window: window,
                                          image: NSImage(cgImage: cgImage, size: window.frame.size)))
                continue
            }
            if !triedFetchingContent {
                triedFetchingContent = true
                do {
                    content = try await SCShareableContent
                        .excludingDesktopWindows(false, onScreenWindowsOnly: false)
                } catch {
                    NSLog("notchtray: SCShareableContent failed: \(error)")
                }
            }
            guard let scWindow = content?.windows.first(where: { $0.windowID == window.id }) else {
                continue
            }
            let scale = scale(for: window.frame)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            do {
                let cgImage = try await SCScreenshotManager
                    .captureImage(contentFilter: filter, configuration: config)
                items.append(CapturedItem(window: window,
                                          image: NSImage(cgImage: cgImage, size: window.frame.size)))
            } catch {
                NSLog("notchtray: capture of \(window.id) failed: \(error)")
            }
        }
        return items
    }
}
