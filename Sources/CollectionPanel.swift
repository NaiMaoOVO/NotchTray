// 收纳面板：入口图标下方弹出的下拉面板，网格展示所有被收纳的图标，支持搜索。
// 窗口机制（无边框 NSPanel + acceptsFirstMouse + 全局点击关闭）参考
// menubar-hide (github.com/junior-rj/menubar-hide, MIT) 的 HiddenItemsPanel，见 README 致谢。
// 面板内容为 NotchTray 原创的搜索 + 网格布局。

import AppKit
import SwiftUI

// 无边框窗口默认拒绝成为 key window；不成为 key，按钮和 Esc 监听都是死的。
// .nonactivatingPanel 让 LSUIElement 应用在面板持有键盘焦点时也不抢占前台（Spotlight 同款机制）。
private final class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// 非 key 窗口的第一次点击通常只用来聚焦；接受它，单击图标即可生效。
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class CollectionPanel {
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private static let edgeInset: CGFloat = 4

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(items: [CapturedItem], below anchorFrame: NSRect,
              onClick: @escaping @MainActor (CapturedItem) -> Void,
              onPin: @escaping @MainActor (CapturedItem) -> Void,
              onRearrange: @escaping @MainActor () -> Void) {
        close()

        let hosting = FirstMouseHostingView(rootView: PanelContentView(
            items: items,
            onClick: { [weak self] item in
                Task { @MainActor in
                    self?.close()
                    onClick(item)
                }
            },
            onPin: { [weak self] item in
                Task { @MainActor in
                    self?.close()
                    onPin(item)
                }
            },
            onRearrange: { [weak self] in
                Task { @MainActor in
                    self?.close()
                    onRearrange()
                }
            }))
        hosting.setFrameSize(hosting.fittingSize)

        // 锚点是入口按钮，永远在菜单栏那块屏上；NSScreen.main 是键盘焦点所在屏，
        // 多屏时会把面板钳到错误的显示器上
        let screen = Self.screenFrame(containing: anchorFrame, screens: NSScreen.screens.map(\.visibleFrame))
        var size = hosting.frame.size
        size.width = min(size.width, screen.width - 2 * Self.edgeInset)
        hosting.setFrameSize(size)

        let panel = ClickablePanel(contentRect: NSRect(origin: .zero, size: size),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isReleasedWhenClosed = false

        let x = max(screen.minX + Self.edgeInset,
                    min(anchorFrame.maxX - panel.frame.width, screen.maxX - panel.frame.width - Self.edgeInset))
        panel.setFrameOrigin(NSPoint(x: x, y: anchorFrame.minY - panel.frame.height - 6))
        panel.orderFrontRegardless()
        panel.makeKey() // 搜索框和按钮需要 key 状态；不会激活 App
        self.panel = panel

        // 点击面板外或按 Esc 关闭
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                           handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                if panel.frame.contains(NSEvent.mouseLocation) { return }
                self.close()
            }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil } // Esc
            return event
        }) {
            monitors.append(monitor)
        }
    }

    static func screenFrame(containing anchor: NSRect, screens: [NSRect]) -> NSRect {
        let mid = NSPoint(x: anchor.midX, y: anchor.midY)
        return screens.first { $0.minX <= mid.x && mid.x < $0.maxX } ?? screens.first ?? .zero
    }

    func close() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - 整理模式提示浮窗

@MainActor
final class HintPanel {
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(below anchorFrame: NSRect, onDone: @escaping @MainActor () -> Void) {
        close()
        let hosting = FirstMouseHostingView(rootView: HintView(onDone: onDone))
        hosting.setFrameSize(hosting.fittingSize)
        let screen = CollectionPanel.screenFrame(containing: anchorFrame, screens: NSScreen.screens.map(\.visibleFrame))
        let panel = ClickablePanel(contentRect: NSRect(origin: .zero, size: hosting.frame.size),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isReleasedWhenClosed = false
        let x = max(screen.minX + 8, min(screen.midX - panel.frame.width / 2,
                                         screen.maxX - panel.frame.width - 8))
        panel.setFrameOrigin(NSPoint(x: x, y: anchorFrame.minY - panel.frame.height - 8))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct HintView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("整理模式")
                .font(.system(size: 12, weight: .semibold))
            Text("按住 ⌘ 拖动图标：放到 # 左侧＝收进收纳盘，右侧＝常驻菜单栏。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 260, alignment: .leading)
            Button("完成，收起") { onDone() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 面板内容（SwiftUI）

private struct PanelContentView: View {
    let items: [CapturedItem]
    let onClick: (CapturedItem) -> Void
    let onPin: (CapturedItem) -> Void
    let onRearrange: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [CapturedItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { $0.label.localizedCaseInsensitiveContains(q) }
    }

    private let columns = Array(repeating: GridItem(.fixed(76), spacing: 2), count: 5)

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(items.isEmpty ? "没有隐藏的图标" : "已收纳 \(items.count) 个图标")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if !items.isEmpty {
                    TextField("搜索", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 120)
                        .focused($searchFocused)
                }
            }

            if items.isEmpty {
                Text("右键入口图标选「整理图标…」，按住 ⌘ 把图标拖到 # 左边即可收进这里")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(filtered) { item in
                        PanelItemCell(item: item, onClick: onClick, onPin: onPin)
                    }
                }
                if filtered.isEmpty {
                    Text("无匹配的图标")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 6)
                }
            }

            HStack {
                Button("整理图标…") { onRearrange() }
                    .font(.system(size: 11))
                Spacer()
                Text("点击图标唤起原菜单 · 右键图标设为常驻")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(width: 428)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { searchFocused = true }
    }
}

private struct PanelItemCell: View {
    let item: CapturedItem
    let onClick: (CapturedItem) -> Void
    let onPin: (CapturedItem) -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            onClick(item)
        } label: {
            VStack(spacing: 4) {
                Image(nsImage: item.image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                Text(item.label)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 2)
            .frame(width: 76)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.accentColor.opacity(isHovering ? 0.18 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("常驻菜单栏（不再收纳）") { onPin(item) }
        }
        .help(item.label)
        // 位图图标无法被读屏软件识别，用名字补上
        .accessibilityLabel(item.label)
    }
}
