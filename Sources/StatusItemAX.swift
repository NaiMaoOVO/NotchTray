// 通过辅助功能（AX）API 操作其他 App 的状态图标：
// - 在图标位于屏幕内时（闪现展开期间）按坐标命中它的 AXButton，读取无障碍标题
// - 缓存按钮引用：图标回到屏幕外后，对按钮执行 AXPress 仍有效——
//   点击面板图标时完全不需要展开菜单栏，菜单直接弹出

import ApplicationServices
import AppKit

@MainActor
enum StatusItemAX {
    private static let systemWideElement = AXUIElementCreateSystemWide()

    /// 图标必须在屏幕内（整理模式 / 闪现展开期间调用）。
    /// 在 point 处命中元素并向上回溯（最多 5 层）找到 AXButton。
    static func buttonElement(at point: CGPoint) -> AXUIElement? {
        var elementRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWideElement,
                                                Float(point.x), Float(point.y),
                                                &elementRef) == .success,
              let found = elementRef
        else { return nil }
        var current = found
        for _ in 0..<5 {
            if role(of: current) == "AXButton" { return current }
            guard let parent = elementAttribute(current, kAXParentAttribute) else { return nil }
            current = parent
        }
        return nil
    }

    /// 图标的可读名字：AXTitle > AXDescription > AXHelp
    static func title(of element: AXUIElement) -> String? {
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
            if let value = rawAttribute(element, name) as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    /// 对按钮执行"按下"。菜单直接弹出，图标无需在屏幕内
    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if error != .success {
            NSLog("notchtray: AXPress failed (\(error.rawValue))")
            return false
        }
        return true
    }

    private static func role(of element: AXUIElement) -> String? {
        rawAttribute(element, kAXRoleAttribute) as? String
    }

    private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let raw = rawAttribute(element, name),
              CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    private static func rawAttribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &valueRef) == .success else { return nil }
        return valueRef
    }
}
