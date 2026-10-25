// 扫描状态栏的图标窗口。
// 基于 menubar-hide (github.com/junior-rj/menubar-hide, MIT) 的实现改编，见 README 致谢。
//
// macOS 26 上状态图标窗口由 Control Center 托管（ownerName/pid 无法识别归属 App），
// 且窗口服务器会把 10000pt 的分隔条压到约 5016pt。所以按"形状"发现：
// 找到超宽的分隔条窗口，取紧贴它左侧的一串连续图标。

import AppKit

struct MenuBarItemWindow: Identifiable {
    let id: CGWindowID
    let frame: CGRect // CG 全局坐标（原点在左上角）
    let ownerName: String
    /// 窗口归属进程：Tahoe 上状态图标窗口全由 Control Center 托管，
    /// AX 查询（命名 / AXPress）要用它
    let ownerPID: pid_t
    /// 窗口标题：拿到屏幕录制权限后 CGWindowList 会返回，常是图标的辅助功能名称
    let title: String
}

struct CapturedItem: Identifiable {
    let window: MenuBarItemWindow
    let image: NSImage
    /// 面板里展示的名字：窗口标题 > ownerName > "图标 N"
    var label: String = ""
    var id: CGWindowID { window.id }
}

enum MenuBarItemScanner {
    static func supportsPerItemWindows(majorVersion: Int) -> Bool { majorVersion < 27 }
    static let isPerItemWindowModelAvailable =
        supportsPerItemWindows(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)

    /// 2500 能排除真实图标和 NotchNook 这类整条覆盖层（≤ 屏宽），同时匹配被钳制的分隔条（~5016）
    private static let separatorMinWidth: CGFloat = 2_500
    /// 两个相邻隐藏图标之间允许的最大间隙；超过说明跑到了另一块屏幕的状态栏
    private static let contiguityGap: CGFloat = 50

    static func hiddenItems() -> [MenuBarItemWindow] {
        hiddenItems(among: statusWindows())
    }

    static func hiddenItems(among windows: [MenuBarItemWindow]) -> [MenuBarItemWindow] {
        // 主屏上收起状态的分隔条 = 最靠右的超宽状态窗口
        guard let separator = windows
            .filter({ $0.frame.width >= separatorMinWidth })
            .max(by: { $0.frame.minX < $1.frame.minX })
        else { return [] }

        // 从分隔条左缘向左走；隐藏图标是连续的，大间隙意味着到了另一块屏
        var result: [MenuBarItemWindow] = []
        var edge = separator.frame.minX
        let candidates = windows
            .filter { $0.frame.maxX <= separator.frame.minX + 1 && $0.frame.width < separatorMinWidth }
            .sorted { $0.frame.maxX > $1.frame.maxX }
        for window in candidates {
            guard edge - window.frame.maxX <= contiguityGap else { break }
            result.append(window)
            edge = window.frame.minX
        }
        return result.sorted { $0.frame.minX < $1.frame.minX }
    }

    static func frame(of windowID: CGWindowID) -> CGRect? {
        statusWindows().first { $0.id == windowID }?.frame
    }

    /// 状态层的指纹（窗口 ID + 位置），用于判断菜单栏是否已经稳定
    static func statusItemFingerprint() -> Set<String> {
        Set(statusWindows().map { "\($0.id)@\(Int($0.frame.minX.rounded()))" })
    }

    private static func statusWindows() -> [MenuBarItemWindow] {
        guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == statusLayer,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict),
                  frame.width > 0, frame.height > 0
            else { return nil }
            return MenuBarItemWindow(id: windowID,
                                     frame: frame,
                                     ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
                                     ownerPID: info[kCGWindowOwnerPID as String] as? pid_t ?? 0,
                                     title: info[kCGWindowName as String] as? String ?? "")
        }
    }
}
