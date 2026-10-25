// 通过辅助功能（AX）API 操作其他 App 的状态图标：
// - 在图标位于屏幕内时（闪现展开期间）按坐标命中它的 AXButton，读取无障碍标题
// - 缓存按钮引用：图标回到屏幕外后，对按钮执行 AXPress 仍有效——
//   点击面板图标时完全不需要展开菜单栏，菜单直接弹出
// - 偏好位置反查：读各 App 存档的"NSStatusItem Preferred Position"，
//   按屏幕坐标把匿名的"Item-N"图标映射回归属 App

import ApplicationServices
import AppKit

@MainActor
enum StatusItemAX {
    private static let systemWideElement = AXUIElementCreateSystemWide()

    /// 图标必须在屏幕内（整理模式 / 闪现展开期间调用）。
    /// 在 point 处命中元素并向上回溯（最多 5 层）找到 AXButton；
    /// 向上找不到再向下探（命中点可能落在按钮的容器上）
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
            guard let parent = elementAttribute(current, kAXParentAttribute) else { break }
            current = parent
        }
        var buttons: [AXUIElement] = []
        collectButtons(from: found, into: &buttons, depth: 0)
        return buttons.first
    }

    private static func collectButtons(from element: AXUIElement, into buttons: inout [AXUIElement], depth: Int) {
        guard depth < 3, buttons.count < 8 else { return }
        if role(of: element) == "AXButton" {
            buttons.append(element)
            return
        }
        guard let raw = rawAttribute(element, kAXChildrenAttribute),
              let list = raw as? [AnyObject] else { return }
        for item in list where CFGetTypeID(item) == AXUIElementGetTypeID() {
            collectButtons(from: unsafeBitCast(item, to: AXUIElement.self), into: &buttons, depth: depth + 1)
        }
    }

    /// 图标的可读名字：AXTitle > AXDescription > AXValue > AXHelp
    static func title(of element: AXUIElement) -> String? {
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
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

/// 匿名状态图标的身份反查：macOS 会把每个状态图标的 x 坐标
/// 以 "NSStatusItem Preferred Position <名>" 存进归属 App 的偏好域，
/// 读出来按坐标匹配就能把窗口映射回 App（沙盒 App 的域读不到，尽力而为）
@MainActor
enum StatusBarIdentity {
    struct Entry {
        let x: CGFloat
        let name: String
    }

    static func positionMap() -> [Entry] {
        var entries: [Entry] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  let defaults = UserDefaults(suiteName: bundleID) else { continue }
            for (key, value) in defaults.dictionaryRepresentation()
            where key.hasPrefix("NSStatusItem Preferred Position ") {
                guard let x = value as? Double, x > 0, x < 20_000 else { continue }
                entries.append(Entry(x: CGFloat(x), name: app.localizedName ?? bundleID))
            }
        }
        return entries
    }

    static func name(at x: CGFloat, in entries: [Entry]) -> String? {
        guard let closest = entries.min(by: { abs($0.x - x) < abs($1.x - x) }),
              abs(closest.x - x) < 12 else { return nil }
        return closest.name
    }
}
