// 图标组织器：使用频率追踪 + 三种排序模式（频率 / 菜单栏顺序 / 手动）。
// 频率按图标的显示名计数（窗口 ID 会随 App 重启变化，名字是稳定键）。

import AppKit

enum SortMode: String, CaseIterable, Identifiable {
    case frequency
    case bar
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .frequency: return "频率"
        case .bar: return "栏序"
        case .manual: return "手动"
        }
    }
}

@MainActor
final class IconOrganizer {
    private let defaults = UserDefaults.standard
    private let countsKey = "notchtray.usageCounts"
    private let modeKey = "notchtray.sortMode"
    private let manualOrderKey = "notchtray.manualOrder"

    private(set) var sortMode: SortMode
    private var counts: [String: Int]
    private(set) var manualOrder: [String]

    init() {
        sortMode = SortMode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? .frequency
        counts = defaults.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
        manualOrder = defaults.stringArray(forKey: manualOrderKey) ?? []
    }

    func usage(of label: String) -> Int {
        counts[label] ?? 0
    }

    func recordUse(of label: String) {
        guard !label.isEmpty else { return }
        counts[label, default: 0] += 1
        defaults.set(counts, forKey: countsKey)
    }

    func setSortMode(_ mode: SortMode) {
        sortMode = mode
        defaults.set(mode.rawValue, forKey: modeKey)
    }

    func commitManualOrder(_ labels: [String]) {
        manualOrder = labels
        defaults.set(labels, forKey: manualOrderKey)
    }

    /// 按当前模式排序。输入 items 应已是菜单栏顺序（栏序），
    /// 频率模式按次数降序、平局保持栏序；手动模式按记住的顺序、新图标排在后面
    func sorted(_ items: [CapturedItem]) -> [CapturedItem] {
        switch sortMode {
        case .bar:
            return items
        case .frequency:
            return items.enumerated()
                .sorted { a, b in
                    let ua = usage(of: a.element.label)
                    let ub = usage(of: b.element.label)
                    if ua != ub { return ua > ub }
                    return a.offset < b.offset
                }
                .map(\.element)
        case .manual:
            return items.enumerated()
                .sorted { a, b in
                    let ia = manualOrder.firstIndex(of: a.element.label) ?? Int.max
                    let ib = manualOrder.firstIndex(of: b.element.label) ?? Int.max
                    if ia != ib { return ia < ib }
                    return a.offset < b.offset
                }
                .map(\.element)
        }
    }
}
