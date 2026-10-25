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

/// 匿名状态图标的身份反查。macOS 把每个状态图标的"距右边缘距离"存进
/// 归属 App 偏好域的 "NSStatusItem Preferred Position <名>" 键；
/// 换算成屏幕绝对 x 后按坐标匹配，把窗口映射回归属 App。
/// 覆盖：运行中 App 的常规域 + 沙盒 App 的容器 plist（苹果系域跳过）
@MainActor
enum StatusBarIdentity {
    struct Entry {
        /// 存档值：距所在屏右边缘的点数（值越大越靠左）
        let stored: CGFloat
        let name: String
    }

    private static var cache: (entries: [Entry], at: Date)?
    private static let cacheTTL: TimeInterval = 60
    /// 换算误差容忍：存档值与绝对坐标之间隔着图标宽度等未知偏移
    private static let tolerance: CGFloat = 26

    static func positionMap() -> [Entry] {
        if let cache, Date().timeIntervalSince(cache.at) < cacheTTL { return cache.entries }
        var entries: [Entry] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  !bundleID.hasPrefix("com.apple."), bundleID != "local.notchtray"
            else { continue }
            appendDomain(bundleID, displayName: app.localizedName ?? bundleID, into: &entries)
        }
        scanContainers(into: &entries)
        NSLog("notchtray: position map has \(entries.count) entries")
        cache = (entries, Date())
        return entries
    }

    /// windowX 为 CG 全局绝对坐标（原点左上，X 轴同 AppKit）
    static func name(at windowX: CGFloat, in entries: [Entry]) -> String? {
        guard let screen = NSScreen.screens.first else { return nil }
        let maxX = screen.frame.maxX
        guard let closest = entries.min(by: {
            abs(maxX - $0.stored - windowX) < abs(maxX - $1.stored - windowX)
        }), abs(maxX - closest.stored - windowX) <= tolerance else { return nil }
        return closest.name
    }

    private static func appendDomain(_ bundleID: String, displayName: String, into entries: inout [Entry]) {
        guard let defaults = UserDefaults(suiteName: bundleID) else { return }
        for (key, value) in defaults.dictionaryRepresentation()
        where key.hasPrefix("NSStatusItem Preferred Position ") {
            if let x = value as? Double, x > 0, x < 4_000 {
                entries.append(Entry(stored: CGFloat(x), name: displayName))
            }
        }
    }

    /// 沙盒 App 的偏好存在 ~/Library/Containers/<...>/Data/Library/Preferences/<bundle-id>.plist，
    /// 直接读 plist 文件（目录名可能是 UUID，但 plist 文件名一定是 bundle id）
    private static func scanContainers(into entries: inout [Entry]) {
        let fm = FileManager.default
        let containers = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers")
        guard let dirs = try? fm.contentsOfDirectory(at: containers, includingPropertiesForKeys: nil) else { return }
        for dir in dirs {
            let prefs = dir.appendingPathComponent("Data/Library/Preferences")
            guard let files = try? fm.contentsOfDirectory(at: prefs, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "plist" {
                let bundleID = file.deletingPathExtension().lastPathComponent
                guard !bundleID.hasPrefix("com.apple."), bundleID != "local.notchtray",
                      let dict = NSDictionary(contentsOf: file) as? [String: Any] else { continue }
                var matched = false
                for (key, value) in dict where key.hasPrefix("NSStatusItem Preferred Position ") {
                    if let x = value as? Double, x > 0, x < 4_000 {
                        entries.append(Entry(stored: CGFloat(x), name: displayName(forBundleID: bundleID)))
                        matched = true
                    }
                }
                _ = matched
            }
        }
    }

    static func displayName(forBundleID bundleID: String) -> String {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           let name = app.localizedName { return name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let fm = FileManager.default
            let shown = fm.displayName(atPath: url.path)
            if !shown.isEmpty && shown != url.deletingPathExtension().lastPathComponent {
                return shown
            }
            if let bundle = Bundle(url: url),
               let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                   ?? (bundle.infoDictionary?["CFBundleName"] as? String) {
                return name
            }
        }
        return bundleID
    }
}
