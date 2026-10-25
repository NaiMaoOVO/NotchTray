// 把面板里的点击转发给真实的状态图标（临时展开后合成 CGEvent 点击）。
// 基于 menubar-hide (github.com/junior-rj/menubar-hide, MIT) 的实现改编，见 README 致谢。
// 需要"辅助功能"权限。

import AppKit
import ApplicationServices

@MainActor
enum ClickForwarder {
    /// 不弹系统提示的检查——调用方自己弹对话框，避免双重弹窗
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 触发系统的辅助功能授权提示（同时把 App 登记进隐私列表）
    static func promptForAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// `point` 为 CG 全局坐标（原点左上），与扫描器的 frame 同一坐标系
    static func postClick(at point: CGPoint) {
        let restorePoint = CGEvent(source: nil)?.location

        // 先悬停：部分状态图标要先看到光标到达才有反应
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)

        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                mouseCursorPosition: point, mouseButton: .left)
            // 默认 clickState 0 会被大多数处理器当作无效点击忽略
            event?.setIntegerValueField(.mouseEventClickState, value: 1)
            event?.post(tap: .cghidEventTap)
        }

        if let restorePoint {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                    mouseCursorPosition: restorePoint, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        NSLog("notchtray: synthetic click posted at (\(point.x), \(point.y))")
    }

    /// 合成 ⌘ 拖拽：把一个状态图标从一个位置拖到另一个位置。
    /// NSStatusItem 原生支持 ⌘ 拖动重排，拖完 macOS 会自动记住新位置。
    /// 需要"辅助功能"权限。调用前图标必须在屏幕内。
    static func postCommandDrag(from point: CGPoint, toX: CGFloat) {
        let flags = CGEventFlags.maskCommand
        let source = CGEventSource(stateID: .combinedSessionState)

        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        usleep(80_000) // 等 AppKit 进入拖拽态

        let steps = 14
        for step in 1...steps {
            let x = point.x + (toX - point.x) * CGFloat(step) / CGFloat(steps)
            let moved = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                mouseCursorPosition: CGPoint(x: x, y: point.y), mouseButton: .left)
            moved?.flags = flags
            moved?.post(tap: .cghidEventTap)
            usleep(25_000)
        }
        usleep(80_000) // 停在目标处再松手，确保落点被接受

        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                         mouseCursorPosition: CGPoint(x: toX, y: point.y), mouseButton: .left)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
        NSLog("notchtray: synthetic ⌘-drag from \(point.x) to \(toX)")
    }
}
