# NotchTray · 刘海收纳盘

把被 MacBook 刘海挡住、挤掉的状态栏图标，全部收进一个下拉收纳面板——图标永远看得见、点得到。

## 使用

1. 首次启动后，**按住 ⌘ 把想收纳的图标拖到 `#` 分隔符左边**（`#` 在入口图标 `▤` 的左侧，可能需要先把图标往右拖一点找到它）。
2. 之后的交互：

| 操作 | 效果 |
|---|---|
| 点击入口图标 `▤`（收起状态） | 弹出收纳面板：网格展示全部图标（含真实名称）+ 搜索框 |
| 点击面板里的图标 | 直接唤起该图标的菜单（AXPress，菜单栏不动、不闪现） |
| 悬停面板图标 | 底部状态行显示该图标的实时状态（AX 动态读取）+ 使用次数 |
| 拖动面板图标 | 手动排序，自动记住顺序 |
| 排序切换（面板底部） | 频率（默认，按点击次数降序）/ 栏序（菜单栏原顺序）/ 手动 |
| 右键面板里的图标 | 「常驻菜单栏」——自动把它拖到分隔符右侧，之后不再收纳 |
| 面板底部「整理图标…」/ 右键入口图标 | 整理模式：侧向展开全部图标 + 悬浮提示，⌘ 拖动自由决定收纳/常驻 |
| 点击入口图标（展开状态） | 收起图标 |
| 按住 ⌥ 点击入口图标 | 侧向展开/收起（⌘ 拖动重排图标时用） |
| 快捷键 ⌃⌥H | 等同于点击入口图标 |
| 右键入口图标 | 菜单：侧向展开 / 整理图标 / 登录时启动 / 关于 / 退出 |

图标名称来自辅助功能 API（AX）读取的图标无障碍标题；面板打开时会有一次约 300ms 的「闪现展开」用于截图和收集名称（屏幕外的窗口截不到图），之后点击图标完全不会再展开菜单栏。

## 需要的权限（仅面板功能）

| 权限 | 用途 | 授权时机 |
|---|---|---|
| 屏幕录制 | 图标属于其他 App，只能截图它们的窗口才能画进面板 | 首次打开面板时引导；**授权后需重启 App** |
| 辅助功能 | 把你在面板里的点击转发给真实图标 | 首次点击面板图标时引导 |

不截图、不落盘：只在面板打开期间在内存里持有图标窗口的即时截图。

## 卸载

1. 右键菜单栏托盘图标 → **退出 NotchTray**（退出时会自动展开菜单栏，各 App 图标的位置由它们自己记忆，无需手动处理）
2. 把 `/Applications/NotchTray.app` 拖进废纸篓
3. 可选的残留清理：
   - `defaults delete local.notchtray`——删除应用设置（排序模式、手动命名、使用频率统计）
   - 系统设置 › 隐私与安全性 里残留的授权记录可手动移除，或终端执行 `tccutil reset ScreenCapture local.notchtray && tccutil reset Accessibility local.notchtray`
   - 日志文件 `~/Library/Logs/NotchTray.log`

## 下载与构建

**下载**：到 [Releases 页面](https://github.com/NaiMaoOVO/NotchTray/releases) 下载最新的 `NotchTray-x.x.x.dmg`，打开后把 NotchTray 拖进「应用程序」文件夹即可（放进去后「登录时启动」才能稳定生效）。

**源码构建**：不依赖 Xcode，只要有 Swift 命令行工具（Xcode Command Line Tools）：

```bash
./build.sh
# 产物: build/NotchTray.app + dist/NotchTray-<版本>.dmg
open build/NotchTray.app
```

已知限制（macOS 26 Tahoe）：
- 状态图标窗口由 Control Center 托管，图标名称通过 AX 无障碍标题获取；个别 App 不设置无障碍标题时会显示"图标 N"。
- 面板打开时有约 300ms 的闪现展开（截图+收集名称需要）；点击图标本身不再展开菜单栏。
- macOS 27 起菜单栏重写为单窗口 + 系统 `«` 溢出，本工具的面板机制不可用（入口图标会提示）。
- 图标位置记忆：各 App 自己记住图标位置；本工具在启动/退出时会保护自己两个图标的位置不被"挤到屏幕外"的坏记录污染。

## 工作原理

- **隐藏**：Hidden Bar 的经典技巧——一个膨胀到 10000pt 的分隔图标把左边所有图标推出屏幕（窗口服务器会钳到 ~5016pt，效果相同）。
- **面板**：Ice 的 Ice Bar 技术路线——用 `CGWindowList` 找到被推走的状态图标窗口，ScreenCaptureKit 逐个截图，在无边框 NSPanel 里展示，点击用合成 `CGEvent` 转发给真实图标；屏幕外的窗口截不到时做 300ms「闪现展开」补截。
- **Tahoe 兼容**：启动后等菜单栏布局稳定（登录风暴结束）才第一次收起；启动时先钉住自己图标的位置，防止被挤到屏幕外；退出前自动展开还原。

## 致谢与许可

核心机制（扫描/截图/点击转发/收起几何）改编自 [menubar-hide](https://github.com/junior-rj/menubar-hide)（MIT © Sparrow Serviços e Soluções em Informática），其技术致谢 [Hidden Bar](https://github.com/dwarvesf/hidden)（MIT，膨胀分隔技巧）与 [Ice](https://github.com/jordanbaird/Ice)（GPL-3，面板概念——仅作技术参考，未复制其代码）。

menubar-hide 的 MIT 许可证全文见 `THIRD_PARTY_NOTICES.md`。收纳面板的搜索 + 网格 UI 为 NotchTray 原创。
