// 收纳面板：入口图标下方弹出的下拉面板，网格展示所有被收纳的图标。
// 支持：搜索、三种排序（频率/栏序/手动）、面板内拖拽排序、悬停查看实时状态、
// 右键设为常驻。窗口机制（无边框 NSPanel + acceptsFirstMouse + 全局点击关闭）
// 参考 menubar-hide (github.com/junior-rj/menubar-hide, MIT)，见 README 致谢。

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// 无边框窗口默认拒绝成为 key window；不成为 key，按钮和 Esc 监听都是死的。
// .nonactivatingPanel 让 LSUIElement 应用在面板持有键盘焦点时也不抢占前台（Spotlight 同款机制）。
private final class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// 非 key 窗口的第一次点击通常只用来聚焦；接受它，单击图标即可生效。
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 控制器注入面板的排序/状态能力
struct PanelContext {
    let sortMode: SortMode
    /// 用当前模式给列表排序（控制器侧持有 IconOrganizer）
    let resort: @MainActor ([CapturedItem]) -> [CapturedItem]
    let onSortChange: @MainActor (SortMode) -> Void
    /// 手动拖拽结束，提交顺序
    let onReorder: @MainActor ([String]) -> Void
    /// 悬停时取图标实时状态（AX 动态读取 + 使用次数）
    let liveStatus: @MainActor (CapturedItem) -> String
}

@MainActor
final class CollectionPanel {
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private static let edgeInset: CGFloat = 4

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(items: [CapturedItem], below anchorFrame: NSRect,
              context: PanelContext,
              onClick: @escaping @MainActor (CapturedItem) -> Void,
              onPin: @escaping @MainActor (CapturedItem) -> Void,
              onRearrange: @escaping @MainActor () -> Void) {
        close()

        let hosting = FirstMouseHostingView(rootView: PanelContentView(
            items: items,
            context: context,
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
    @State private var displayItems: [CapturedItem]
    let context: PanelContext
    let onClick: (CapturedItem) -> Void
    let onPin: (CapturedItem) -> Void
    let onRearrange: () -> Void

    @State private var query = ""
    @State private var sortMode: SortMode
    @State private var draggingLabel: String?
    @State private var hoverStatus: String?
    @FocusState private var searchFocused: Bool

    init(items: [CapturedItem], context: PanelContext,
         onClick: @escaping (CapturedItem) -> Void,
         onPin: @escaping (CapturedItem) -> Void,
         onRearrange: @escaping () -> Void) {
        _displayItems = State(initialValue: items)
        _sortMode = State(initialValue: context.sortMode)
        self.context = context
        self.onClick = onClick
        self.onPin = onPin
        self.onRearrange = onRearrange
    }

    private var filtered: [CapturedItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return displayItems }
        return displayItems.filter { $0.label.localizedCaseInsensitiveContains(q) }
    }

    private let columns = Array(repeating: GridItem(.fixed(76), spacing: 2), count: 5)

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(displayItems.isEmpty ? "没有隐藏的图标" : "已收纳 \(displayItems.count) 个图标")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if !displayItems.isEmpty {
                    TextField("搜索", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 120)
                        .focused($searchFocused)
                }
            }

            if displayItems.isEmpty {
                Text("右键入口图标选「整理图标…」，按住 ⌘ 把图标拖到 # 左边即可收进这里")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(filtered) { item in
                        PanelItemCell(
                            item: item,
                            isDragging: draggingLabel == item.label,
                            onClick: onClick,
                            onPin: onPin,
                            onHover: { hovering in
                                if hovering {
                                    hoverStatus = context.liveStatus(item)
                                } else if hoverStatus != nil {
                                    hoverStatus = nil
                                }
                            },
                            onDragStart: { draggingLabel = item.label },
                            dropDelegate: ReorderDropDelegate(
                                target: item,
                                items: $displayItems,
                                draggingLabel: $draggingLabel
                            ) { labels in
                                // 拖拽即手动排序：提交顺序并切换模式
                                context.onReorder(labels)
                                sortMode = .manual
                            }
                        )
                    }
                }
                if filtered.isEmpty {
                    Text("无匹配的图标")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 6)
                }
            }

            HStack(spacing: 8) {
                Picker("排序", selection: $sortMode) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .onChange(of: sortMode) { newMode in
                    context.onSortChange(newMode)
                    displayItems = context.resort(displayItems)
                }
                Spacer()
                Button("整理图标…") { onRearrange() }
                    .font(.system(size: 11))
            }

            Text(hoverStatus ?? "点击图标唤起原菜单 · 右键设为常驻 · 拖动可手动排序")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(width: 428)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { searchFocused = true }
    }
}

// MARK: - 拖拽重排

private struct ReorderDropDelegate: DropDelegate {
    let target: CapturedItem
    @Binding var items: [CapturedItem]
    @Binding var draggingLabel: String?
    let commit: ([String]) -> Void

    private func index(of label: String) -> Int? {
        items.firstIndex { $0.label == label }
    }

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingLabel, dragging != target.label,
              let from = index(of: dragging), let to = index(of: target.label)
        else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            items.move(fromOffsets: IndexSet(integer: from),
                       toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingLabel = nil
        commit(items.map(\.label))
        return true
    }
}

// MARK: - 图标格子

private struct PanelItemCell: View {
    let item: CapturedItem
    let isDragging: Bool
    let onClick: (CapturedItem) -> Void
    let onPin: (CapturedItem) -> Void
    let onHover: (Bool) -> Void
    let onDragStart: () -> Void
    let dropDelegate: ReorderDropDelegate
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
            .opacity(isDragging ? 0.35 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            onHover(hovering)
        }
        .onDrag {
            onDragStart()
            return NSItemProvider(object: item.label as NSString)
        }
        .onDrop(of: [UTType.text], delegate: dropDelegate)
        .contextMenu {
            Button("常驻菜单栏（不再收纳）") { onPin(item) }
        }
        .help(item.label)
        // 位图图标无法被读屏软件识别，用名字补上
        .accessibilityLabel(item.label)
    }
}
