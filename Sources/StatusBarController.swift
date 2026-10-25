// NotchTray 主控制器。
// 隐藏机制（膨胀分隔条把左侧图标推出屏幕）来自 Hidden Bar 的经典技巧；
// 面板机制（扫描 + 截图 + 转发点击）的技术路线参考 Ice 与
// menubar-hide (github.com/junior-rj/menubar-hide, MIT)，Tahoe 兼容性处理
// （Control Center 托管、位置钉住、闪现展开截图、启动风暴等待）改编自后者，见 README 致谢。

import AppKit
import CryptoKit
import ServiceManagement

@MainActor
final class StatusBarController {
    /// macOS 26 及以前：每个状态图标一个窗口（面板模式可用）
    private static let legacyModel = MenuBarItemScanner.isPerItemWindowModelAvailable
    /// 启动后轮询状态层，每 2s 一次；3 次相同视为菜单栏稳定
    private static let initialStablePolls = 3
    private static let initialMaxPolls = 60 // ~120s 上限，防止登录风暴一直不停

    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let panel = CollectionPanel()
    private let hint = HintPanel()
    private let organizer = IconOrganizer()
    private var initialCollapseTask: Task<Void, Never>?
    private var autoCollapseMonitor: Any?
    private var autoCollapseTask: Task<Void, Never>?
    private var isOpeningPanel = false
    /// 图标缓存：一次面板会话里截到的图 + AX 名字 + AX 按钮引用按窗口 ID 复用，
    /// 下次打开面板若窗口没变（App 没重启）就完全不需要闪现展开
    private struct CachedIcon {
        let image: NSImage
        /// 图像内容哈希：手动重命名以此为键，跨重启/重建持久
        let imageKey: String
    }
    private var iconCache: [CGWindowID: CachedIcon] = [:]
    private(set) var isCollapsed = false
    // 新图标入库提醒：周期扫描状态层，发现新窗口就在入口图标上亮一个小圆点
    private var scanTimer: Timer?
    private var seenWindowIDs: Set<CGWindowID> = []
    private var hasNewItems = false
    var hotkeyAvailable = false

    init() {
        guard Self.legacyModel else {
            // macOS 27+ 把菜单栏重写成了单窗口 + 系统「«」溢出菜单，
            // 面板机制失效。MVP 先不支持，给出提示后仅创建入口图标。
            NSLog("notchtray: macOS 27+ 单窗口菜单栏模型，收纳面板不可用")
            toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            separatorItem = toggleItem // 占位，后续不会用到
            configureToggleButton()
            return
        }

        // Tahoe 上挤满的菜单栏会把新状态图标停到屏幕外（x ≈ -4220）并且自动记住坏位置，
        // 所以启动时先把我们两个图标自己的位置钉住（值越大越靠左；分隔条必须在入口左侧）
        Self.pinOwnPositions()

        // 创建顺序在首次启动时重要：新图标从左侧进入，先建入口（最右）再建分隔条
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggleItem.autosaveName = "notchtray_toggle"
        separatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        separatorItem.autosaveName = "notchtray_separator"

        configureToggleButton()
        if let button = separatorItem.button {
            button.image = Self.symbol("number")
            button.setAccessibilityLabel("收纳分隔符")
        }

        scheduleInitialCollapse()
        startScanLoop()
    }

    /// 每 15 秒扫一次状态层：发现"新面孔"被收进来时在入口图标上提示。
    /// 首次扫描只记录基线（启动风暴期间不触发）。
    private func startScanLoop() {
        guard Self.legacyModel else { return }
        scanTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scanTick() }
        }
    }

    private func scanTick() {
        let current = Set(MenuBarItemScanner.hiddenItems().map(\.id))
        if !seenWindowIDs.isEmpty {
            let fresh = current.subtracting(seenWindowIDs)
            if !fresh.isEmpty {
                hasNewItems = true
                updateToggleIcon()
                NSLog("notchtray: \(fresh.count) new item(s) collected, badge on")
            }
        }
        seenWindowIDs = current
    }

    private func configureToggleButton() {
        guard let button = toggleItem.button else { return }
        button.target = self
        button.action = #selector(toggleClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateToggleIcon()
    }

    // MARK: - 位置钉住（仅 macOS 26 及以前）

    private static func pinOwnPositions() {
        let defaults = UserDefaults.standard
        let toggleKey = "NSStatusItem Preferred Position notchtray_toggle"
        let separatorKey = "NSStatusItem Preferred Position notchtray_separator"
        let toggle = defaults.object(forKey: toggleKey) as? Double
        let separator = defaults.object(forKey: separatorKey) as? Double
        // 分隔条必须保持在入口图标左边（值更大）；位置对调说明自动保存已被损坏，重置
        if let t = toggle, let s = separator, t > 0, s > t, t < 4000, s < 4000 {
            NSLog("notchtray: pinned positions toggle=\(t) separator=\(s)")
        } else {
            defaults.set(250, forKey: toggleKey)
            defaults.set(265, forKey: separatorKey)
            NSLog("notchtray: reset positions to defaults (stored toggle=\(String(describing: toggle)) separator=\(String(describing: separator)))")
        }
    }

    // MARK: - 收起 / 展开

    /// 启动后先展开，等菜单栏布局稳定再收起。立即收起会打乱各 App 自动保存的位置，
    /// 登录风暴期间收起还会吞掉晚启动的 App 并损坏它们自己记住的位置。
    private func scheduleInitialCollapse() {
        initialCollapseTask = Task { @MainActor [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(500))) != nil else { return }
            var fingerprint = Set<String>()
            var stablePolls = 0
            for poll in 0..<Self.initialMaxPolls {
                guard let self, !self.isCollapsed, !Task.isCancelled else { return }
                let current = MenuBarItemScanner.statusItemFingerprint()
                if current == fingerprint {
                    stablePolls += 1
                    if stablePolls >= Self.initialStablePolls {
                        NSLog("notchtray: menu bar stable after \(poll + 1) polls, collapsing")
                        self.collapse()
                        return
                    }
                } else {
                    stablePolls = 0
                    fingerprint = current
                }
                guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
            }
            guard let self, !self.isCollapsed, !Task.isCancelled else { return }
            NSLog("notchtray: menu bar never stabilized, collapsing anyway")
            self.collapse()
        }
    }

    func toggle() {
        guard Self.legacyModel else { return }
        if isCollapsed {
            panel.isVisible ? panel.close() : openPanel()
        } else {
            collapse()
        }
    }

    private func collapse() {
        stateWillChange()
        panel.close()
        hint.close()
        separatorItem.length = 10_000 // 窗口服务器会钳到 ~5016，效果不变
        isCollapsed = true
        updateToggleIcon()
    }

    private func expand() {
        stateWillChange()
        panel.close()
        hint.close()
        separatorItem.length = NSStatusItem.variableLength
        isCollapsed = false
        updateToggleIcon()
    }

    /// 收起状态下退出/卸载不能把别人的图标留在屏幕外
    func expandForQuit() {
        guard isCollapsed, Self.legacyModel else { return }
        panel.close()
        separatorItem.length = NSStatusItem.variableLength
        isCollapsed = false
    }

    /// 任何收起/展开都使挂起的自动化失效：过期的自动收起监听会在下一次转发点击的
    /// 合成 mouseUp 上触发，把菜单栏在交互中途拽走
    private func stateWillChange() {
        initialCollapseTask?.cancel()
        initialCollapseTask = nil
        disarmAutoCollapse()
    }

    private func disarmAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        if let monitor = autoCollapseMonitor {
            NSEvent.removeMonitor(monitor)
            autoCollapseMonitor = nil
        }
    }

    private func updateToggleIcon() {
        let name = isCollapsed ? "tray.full" : "tray"
        toggleItem.button?.image = hasNewItems ? Self.badgedSymbol(name) : Self.symbol(name)
        toggleItem.button?.setAccessibilityLabel(isCollapsed ? "打开收纳面板" : "收起图标")
    }

    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    /// 基础符号 + 右上角小圆点（有新图标入库的提示）
    private static func badgedSymbol(_ name: String) -> NSImage? {
        guard let base = symbol(name) else { return nil }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size))
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: 11, y: 10, width: 6, height: 6)).fill()
        image.unlockFocus()
        image.isTemplate = false // 保持红点醒目
        return image
    }

    @objc private func toggleClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else if event?.modifierFlags.contains(.option) == true {
            // 按住 ⌥ 点按 = 侧向展开/收起，供 ⌘ 拖动重排图标用
            isCollapsed ? expand() : collapse()
        } else {
            toggle()
        }
    }

    // MARK: - 收纳面板

    private func openPanel() {
        guard !isOpeningPanel else { return } // 重叠的闪现展开会互相打架
        guard ItemCapturer.hasPermission() else {
            showPermissionAlert(
                message: "需要「屏幕录制」权限",
                informative: "NotchTray 需要屏幕录制权限才能把隐藏的图标画进收纳面板。请在系统设置中授权，然后重启 NotchTray（macOS 要求此权限授权后重启 App 才生效）。",
                settingsAnchor: "Privacy_ScreenCapture",
                beforeOpeningSettings: { ItemCapturer.requestPermission() })
            return
        }
        isOpeningPanel = true
        let anchorFrame = toggleItem.button?.window?.frame ?? .zero
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isOpeningPanel = false }
            let windows = MenuBarItemScanner.hiddenItems()
            let uncached = windows.filter { self.iconCache[$0.id] == nil }
            if !uncached.isEmpty {
                // 闪现展开只为截图：屏幕外的窗口截不到图。
                // 名字与按压都走 AXExtrasMenuBar 实时枚举（可离屏），无需闪现。
                FileLog.write("notchtray: flash-expand for \(uncached.count) new item(s)")
                applySeparatorLength(collapsed: false)
                try? await Task.sleep(for: .milliseconds(320))
                let captured = await ItemCapturer.capture(uncached)
                for item in captured {
                    self.iconCache[item.window.id] = CachedIcon(image: item.image,
                                                                imageKey: Self.imageKey(item.image))
                }
                // 闪现期间用户手动展开了菜单栏，则现状归用户所有，不要强行收回去
                if isCollapsed { applySeparatorLength(collapsed: true) }
            }
            // 截图期间菜单栏被手动展开的话就不再显示面板，避免图标双份出现
            guard isCollapsed else {
                FileLog.write("notchtray: bar expanded during capture, not showing the panel")
                return
            }
            // 收起后重新扫描：停靠位置可能与闪现前不同，AX 树匹配要用最新 frame
            let currentWindows = MenuBarItemScanner.hiddenItems()
            let scan = currentWindows.isEmpty ? windows : currentWindows
            iconCache = iconCache.filter { Set(scan.map(\.id)).contains($0.key) } // 清理已退出的 App
            var items: [CapturedItem] = []
            for window in scan {
                guard let cached = iconCache[window.id] else { continue }
                var item = CapturedItem(window: window, image: cached.image)
                item.label = self.displayName(for: window, cached: cached)
                items.append(item)
            }
            items.sort { $0.window.frame.minX < $1.window.frame.minX }
            var fallbackIndex = 0
            for (index, item) in items.enumerated() where items[index].label.isEmpty {
                fallbackIndex += 1
                items[index].label = "未命名图标 \(fallbackIndex)"
            }
            items = organizer.sorted(items)
            hasNewItems = false // 用户已看过面板，清除新图标提示
            updateToggleIcon()
            FileLog.write("notchtray: showing panel with \(items.count) items (cache hit \(scan.count - uncached.count), mode \(organizer.sortMode.rawValue))")
            let anchor = toggleItem.button?.window?.frame ?? anchorFrame
            panel.show(items: items, below: anchor,
                       context: PanelContext(
                            sortMode: organizer.sortMode,
                            resort: { [weak self] list in self?.organizer.sorted(list) ?? list },
                            onSortChange: { [weak self] mode in self?.organizer.setSortMode(mode) },
                            onReorder: { [weak self] labels in self?.organizer.commitManualOrder(labels) },
                            liveStatus: { [weak self] item in self?.liveStatus(for: item) ?? item.label },
                            onRename: { [weak self] item in self?.renameFlow(for: item) }),
                       onClick: { [weak self] item in self?.forwardClick(to: item) },
                       onPin: { [weak self] item in self?.pinVisible(item) },
                       onRename: { [weak self] item in self?.renameFlow(for: item) },
                       onRearrange: { [weak self] in self?.rearrange() })
        }
    }

    /// 名字解析：手动命名 > AX 标题（extras 树实时读取，可离屏）> 窗口标题 > 空（稍后兜底编号）
    private func displayName(for window: MenuBarItemWindow, cached: CachedIcon) -> String {
        if let manual = manualNames[cached.imageKey] { return manual }
        if let button = StatusItemAX.extrasButton(for: window),
           let title = StatusItemAX.title(of: button), !Self.isGenericName(title) {
            return title
        }
        if !Self.isGenericName(window.title) { return window.title }
        return ""
    }

    /// "Item-0"/"Item 12"/"控制中心" 这类名字不是图标自己的名字
    private static func isGenericName(_ name: String?) -> Bool {
        guard let name else { return true }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if trimmed.range(of: #"^Item[- ]?\d+$"#, options: .regularExpression) != nil { return true }
        let lower = trimmed.lowercased()
        return lower == "控制中心" || lower == "control center"
    }

    /// 悬停时的实时状态：AX 动态读取的标题/描述 + 使用次数
    private func liveStatus(for item: CapturedItem) -> String {
        var parts = [item.label]
        if let button = StatusItemAX.extrasButton(for: item.window),
           let live = StatusItemAX.title(of: button),
           !live.isEmpty, live != item.label, !Self.isGenericName(live) {
            parts.append("· " + live)
        }
        let uses = organizer.usage(of: item.label)
        if uses > 0 {
            parts.append("已点 \(uses) 次")
        }
        return parts.joined(separator: "  ")
    }

    private func applySeparatorLength(collapsed: Bool) {
        separatorItem.length = collapsed ? 10_000 : NSStatusItem.variableLength
    }

    // MARK: - 手动重命名（Tahoe 上匿名图标无公开归属数据，用户命名是最终手段）

    /// 图标图像内容哈希作为键：图标像素不变则键不变，跨重启/重建持久
    static func imageKey(_ image: NSImage) -> String {
        let data = image.tiffRepresentation ?? Data()
        return SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private var manualNames: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "notchtray.manualNames") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "notchtray.manualNames") }
    }

    private func renameFlow(for item: CapturedItem) {
        let alert = NSAlert()
        alert.messageText = "重命名图标"
        alert.informativeText = item.label.hasPrefix("未命名")
            ? "给这个图标起个名字，名字会跟随图标本身，重启后依然生效。"
            : "当前名字「\(item.label)」。改名后同样跟随图标本身。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = item.label.hasPrefix("未命名") ? "" : item.label
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        let key = Self.imageKey(item.image)
        var names = manualNames
        if name.isEmpty {
            names.removeValue(forKey: key)
        } else {
            names[key] = name
        }
        manualNames = names
        FileLog.write("notchtray: manual name for \(key) -> \(name.isEmpty ? "(cleared)" : name)")
    }

    // MARK: - 点击转发

    private func forwardClick(to item: CapturedItem) {
        organizer.recordUse(of: item.label)
        guard ClickForwarder.isTrusted() else {
            showPermissionAlert(
                message: "需要「辅助功能」权限",
                informative: "NotchTray 需要辅助功能权限才能替你点击隐藏的图标。请在系统设置 › 隐私与安全性 › 辅助功能中授权，然后重试。",
                settingsAnchor: "Privacy_Accessibility",
                beforeOpeningSettings: { ClickForwarder.promptForAccessibility() })
            return
        }
        // 快速路径：从宿主进程 AXExtrasMenuBar 实时枚举按钮并按压（不依赖缓存引用，
        // 图标在屏幕外也能按），菜单栏完全不动
        let pressResult = StatusItemAX.pressItem(window: item.window)
        if pressResult == true {
            FileLog.write("notchtray: AXPress ok for \(item.window.id) [\(item.label)]")
            return
        }
        FileLog.write("notchtray: press unavailable/failed (\(String(describing: pressResult))), falling back to expand + synthetic click")
        expand()
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 菜单栏重排是异步的；重试直到图标落回屏幕内。X 在 CG 和 AppKit 坐标系一致
            let toggleMinX = toggleItem.button?.window?.frame.minX ?? -.infinity
            var frame: CGRect?
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(150))
                if let found = MenuBarItemScanner.frame(of: item.window.id),
                   Self.isInMenuBarStrip(found), Self.isConcealableSide(found, toggleMinX: toggleMinX) {
                    frame = found
                    break
                }
            }
            guard let frame else {
                // 展开后仍在屏幕外（比如躲在刘海后）：保持展开让用户点真实的图标
                NSLog("notchtray: item still off-screen after expand")
                armAutoCollapse()
                return
            }
            ClickForwarder.postClick(at: CGPoint(x: frame.midX, y: frame.midY))
            armAutoCollapse()
        }
    }

    // MARK: - 收纳 / 常驻的自由选择

    /// 把面板里的一个图标设为常驻：合成 ⌘ 拖拽把它移到分隔符右侧（入口图标旁）
    private func pinVisible(_ item: CapturedItem) {
        guard Self.legacyModel else { return }
        guard ClickForwarder.isTrusted() else {
            showPermissionAlert(
                message: "需要「辅助功能」权限",
                informative: "NotchTray 需要辅助功能权限才能替你移动图标。请在系统设置 › 隐私与安全性 › 辅助功能中授权，然后重试。",
                settingsAnchor: "Privacy_Accessibility",
                beforeOpeningSettings: { ClickForwarder.promptForAccessibility() })
            return
        }
        panel.close()
        expand()
        Task { @MainActor [weak self] in
            guard let self else { return }
            var frame: CGRect?
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(150))
                if let found = MenuBarItemScanner.frame(of: item.window.id), Self.isInMenuBarStrip(found) {
                    frame = found
                    break
                }
            }
            guard let frame else {
                NSLog("notchtray: cannot locate item for pin, leaving expanded")
                self.armAutoCollapse()
                return
            }
            let toggleMinX = toggleItem.button?.window?.frame.minX ?? (frame.maxX + 30)
            ClickForwarder.postCommandDrag(from: CGPoint(x: frame.midX, y: frame.midY),
                                           toX: toggleMinX - 24)
            try? await Task.sleep(for: .milliseconds(500))
            self.collapse()
        }
    }

    /// 整理模式：侧向展开全部图标 + 悬浮提示，用户 ⌘ 拖动自由决定谁收纳谁常驻
    private func rearrange() {
        guard Self.legacyModel else { return }
        panel.close()
        expand()
        let anchor = toggleItem.button?.window?.frame ?? .zero
        hint.show(below: anchor) { [weak self] in
            self?.collapse()
        }
    }

    /// 点击目标必须真的在某块屏的菜单栏条带里，防止伪造状态层窗口把合成点击引走
    private static func isInMenuBarStrip(_ frame: CGRect) -> Bool {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        let mid = CGPoint(x: frame.midX, y: frame.midY)
        return displays.map(CGDisplayBounds).contains { bounds in
            bounds.contains(mid)
                && frame.minX >= bounds.minX && frame.maxX <= bounds.maxX
                && abs(frame.minY - bounds.minY) <= 2
                && frame.height <= 40
        }
    }

    /// 目标必须还在入口图标左侧（收纳侧）；迁移到右侧的不归我们点
    private static func isConcealableSide(_ frame: CGRect, toggleMinX: CGFloat) -> Bool {
        frame.maxX <= toggleMinX
    }

    /// 转发点击交互结束（通常下一次真实点击 = 关闭图标自己的菜单）后自动收起。
    /// 子菜单需要第二个点击周期；15s 兜底。
    private func armAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = Task { @MainActor [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(400))) != nil else { return } // 跳过自己的合成点击
            guard let controller = self, !controller.isCollapsed else { return }
            if controller.autoCollapseMonitor == nil {
                controller.autoCollapseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                    MainActor.assumeIsolated { self?.finishAutoCollapse() }
                }
                NSLog("notchtray: auto-collapse armed")
            }
            guard (try? await Task.sleep(for: .seconds(15))) != nil else { return }
            self?.finishAutoCollapse()
        }
    }

    private func finishAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        guard let monitor = autoCollapseMonitor else { return }
        NSEvent.removeMonitor(monitor)
        autoCollapseMonitor = nil
        if !isCollapsed { collapse() }
    }

    // MARK: - 右键菜单与对话框

    private func showMenu() {
        let menu = NSMenu()

        let expandItem = NSMenuItem(title: isCollapsed ? "侧向展开（重排图标）" : "收起图标",
                                    action: #selector(sidewaysToggle), keyEquivalent: "")
        expandItem.target = self
        menu.addItem(expandItem)

        let arrangeItem = NSMenuItem(title: "整理图标…", action: #selector(rearrangeMenu), keyEquivalent: "")
        arrangeItem.target = self
        arrangeItem.isEnabled = Self.legacyModel
        menu.addItem(arrangeItem)
        menu.addItem(.separator())

        if !hotkeyAvailable {
            let notice = NSMenuItem(title: "⌃⌥H 不可用（被其他 App 占用）", action: nil, keyEquivalent: "")
            notice.isEnabled = false
            menu.addItem(notice)
        }

        let loginItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        if !Self.legacyModel {
            let notice = NSMenuItem(title: "此 macOS 版本的菜单栏不支持收纳面板", action: nil, keyEquivalent: "")
            notice.isEnabled = false
            menu.addItem(notice)
        }

        menu.addItem(.separator())
        let about = NSMenuItem(title: "关于 NotchTray", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "退出 NotchTray", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.autoenablesItems = false
        // 赋菜单 → 点按钮 → 取消赋值：左键单击保持给 toggle()
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        toggleItem.menu = nil
    }

    @objc private func sidewaysToggle() {
        guard Self.legacyModel else { return }
        isCollapsed ? expand() : collapse()
    }

    @objc private func rearrangeMenu() {
        rearrange()
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "基于 menubar-hide (MIT) 与 Hidden Bar 技术改编",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            runAlert(message: "无法更改登录启动",
                     informative: "macOS 拒绝了更改。把 NotchTray 移到「应用程序」文件夹后重试，或在系统设置 › 通用 › 登录项中手动管理。",
                     buttons: ["好"])
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @discardableResult
    private func runAlert(message: String, informative: String, buttons: [String]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        for title in buttons { alert.addButton(withTitle: title) }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    private func showPermissionAlert(message: String, informative: String,
                                     settingsAnchor: String, beforeOpeningSettings: () -> Void) {
        let response = runAlert(message: message, informative: informative,
                                buttons: ["打开系统设置", "取消"])
        if response == .alertFirstButtonReturn {
            beforeOpeningSettings() // 系统弹窗在这里触发，同时把 App 登记进隐私列表
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
