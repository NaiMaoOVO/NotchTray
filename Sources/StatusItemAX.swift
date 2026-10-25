// 通过辅助功能（AX）API 操作其他 App 的状态图标：
// - 按压：优先从 Control Center 的 AXExtrasMenuBar 实时枚举按钮（按当前位置匹配，
//   包括屏幕外的停靠位置——不依赖缓存引用，绕开"Control Center 重建 AX 树导致引用失效"）
// - 命名：读元素的无障碍标题（Title/Description/Value/Help）
// - 命中检测（屏幕内时）：systemWide 按坐标命中，向上回溯 / 向下探找 AXButton

import ApplicationServices
import AppKit

@MainActor
enum StatusItemAX {
    private static let systemWideElement = AXUIElementCreateSystemWide()
    /// macOS 的状态图标区挂在宿主进程 AX 树的 AXExtrasMenuBar 属性下
    private static let extrasMenuBar = "AXExtrasMenuBar"

    // MARK: - 按压

    /// 实时枚举 AXExtrasMenuBar，按窗口当前 frame（可为停靠的屏幕外位置）匹配按钮并按压。
    /// 返回 nil = 树里找不到匹配；false = 找到但按压失败
    static func pressItem(window: MenuBarItemWindow) -> Bool? {
        guard let button = extrasButton(for: window) else {
            FileLog.write("notchtray: no extras-menubar match for window \(window.id)")
            return nil
        }
        let error = AXUIElementPerformAction(button, kAXPressAction as CFString)
        if error != .success {
            FileLog.write("notchtray: AXPress on extras item failed (\(error.rawValue))")
            return false
        }
        return true
    }

    /// 在宿主进程的 AXExtrasMenuBar 里按 frame 找元素（容忍 ±8pt；重合时取数组序最近者）
    static func extrasButton(for window: MenuBarItemWindow) -> AXUIElement? {
        guard window.ownerPID != 0 else { return nil }
        let app = AXUIElementCreateApplication(window.ownerPID)
        guard let raw = rawAttribute(app, extrasMenuBar),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            FileLog.write("notchtray: AXExtrasMenuBar unavailable (pid \(window.ownerPID))")
            return nil
        }
        let bar = unsafeBitCast(raw, to: AXUIElement.self)
        guard let children = children(of: bar), !children.isEmpty else { return nil }

        // 候选：frame 匹配的元素；多个重合时（停靠位置重叠）用数组序兜底
        var candidates: [(index: Int, element: AXUIElement, distance: CGFloat)] = []
        for (index, child) in children.enumerated() {
            guard let frame = elementFrame(child) else { continue }
            let distance = max(abs(frame.minX - window.frame.minX), abs(frame.minY - window.frame.minY))
            if distance <= 8 {
                candidates.append((index, child, distance))
            }
        }
        guard !candidates.isEmpty else { return nil }
        candidates.sort {
            $0.distance != $1.distance ? $0.distance < $1.distance : $0.index < $1.index
        }
        let element = candidates[0].element
        if role(of: element) == "AXButton" { return element }
        // 命中的是容器：向下探找按钮
        var buttons: [AXUIElement] = []
        collectButtons(from: element, into: &buttons, depth: 0)
        return buttons.first
    }

    // MARK: - 命名

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

    // MARK: - 坐标命中（屏幕内）

    /// 图标必须在屏幕内（闪现展开期间调用）。
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
        guard let list = children(of: element) else { return }
        for child in list {
            collectButtons(from: child, into: &buttons, depth: depth + 1)
        }
    }

    // MARK: - 底层读取

    static func elementFrame(_ element: AXUIElement) -> CGRect? {
        guard let posRaw = rawAttribute(element, kAXPositionAttribute),
              let sizeRaw = rawAttribute(element, kAXSizeAttribute) else { return nil }
        let position = unsafeBitCast(posRaw, to: AXValue.self)
        let size = unsafeBitCast(sizeRaw, to: AXValue.self)
        var point = CGPoint()
        var cgSize = CGSize()
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &cgSize) else { return nil }
        return CGRect(origin: point, size: cgSize)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement]? {
        guard let raw = rawAttribute(element, kAXChildrenAttribute),
              let list = raw as? [AnyObject] else { return nil }
        return list.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (unsafeBitCast(item, to: AXUIElement.self)) : nil
        }
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
