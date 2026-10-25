# NotchTray 开发交接文档

> **维护约定：每完成一轮开发/修复，必须更新本文档**（版本历史、已知问题、待办）。
> 下一个 agent 从这里接手，不需要翻聊天记录。

## 项目概述

NotchTray（刘海收纳盘）：macOS 菜单栏工具，把被 MacBook 刘海挡住/挤掉的状态栏图标收进一个下拉面板（网格 + 搜索 + 排序），点击面板图标直接唤起原菜单。

- 仓库：https://github.com/NaiMaoOVO/NotchTray（SSH：`git@github.com:NaiMaoOVO/NotchTray.git`，已配置可推送）
- 目录：`/Users/chenzixun/Documents/mac状态栏插件/NotchTray`
- 语言/构建：Swift 6.3 + AppKit/SwiftUI，**无 Xcode**，用 swiftc 直接编译（`./build.sh`）
- 当前版本：见 Resources/Info.plist（发布时同步 build.sh 产出的 DMG 名）

## 当前状态（v0.6.0）

已实现：
- 膨胀分隔条隐藏机制（10000pt，窗口服务器钳到 ~5016）——Hidden Bar 技巧
- 收纳面板：图标截图网格 + 搜索 + 三种排序（频率/栏序/手动）+ 拖拽排序 + 键盘导航（方向键/回车）+ 悬停实时状态
- 点击转发三段式：① 实时枚举宿主进程（Control Center）的 AXExtrasMenuBar，按图标当前 frame（含停靠的屏幕外位置）匹配全新按钮引用并 AXPress（免展开快速路径，引用不缓存、不存在失效问题）→ ② 失败则展开菜单栏 + 合成点击（兜底路径，交互结束自动收回）
- 图标缓存（截图 + 名字），重复开面板零闪现；按钮引用 v0.6.0 起改为每次实时枚举、不再缓存（旧"失效作废重抓"机制随之移除）
- 手动重命名：右键面板图标 → 重命名…，以图标图像 SHA256 为键持久化（defaults: notchtray.manualNames），跨重启/重建生效
- 命名链：手动命名 > AX 标题（extras 树实时读，可离屏）> 窗口标题(kCGWindowName) > "未命名图标 N"
- FileLog：~/Library/Logs/NotchTray.log（超 1MB 截断）——统一日志抓不到本应用 NSLog，这是可靠观测手段
- 新图标入库提醒（入口图标红点，15s 扫描）
- ⌃⌥H 全局热键；右键菜单（整理模式/登录启动/退出）
- 稳定签名：自签证书 "NotchTray Dev"（钥匙串里），designated requirement 绑证书指纹——**重新编译不再掉 TCC 授权**
- build.sh 自动装进 /Applications（启动台可见）

## 版本历史

- v0.5.0：键盘导航、新图标入库提醒（badge）
- v0.5.1：AXPress 失效作废机制（后被 v0.6.0 重构取代）、命名过滤 Item-N
- v0.5.2：过滤托管进程名"控制中心"、尝试坐标反查（后证实不可行）、F3 图标改版、安装到 /Applications
- v0.6.0：AXExtrasMenuBar 实时按压重构、手动重命名、FileLog

## 架构（Sources/）

| 文件 | 职责 |
|---|---|
| main.swift / AppDelegate.swift | 入口、生命周期（收起状态退出前必须展开还原） |
| StatusBarController.swift | 核心：创建 NSStatusItem、收起/展开几何、面板调度、点击转发、位置钉住、badge 扫描、右键菜单 |
| MenuBarItemScanner.swift | CGWindowList 扫描状态层窗口；按"形状"找隐藏图标（超宽分隔条右侧连续串） |
| ItemCapturer.swift | CGWindowListCreateImage → ScreenCaptureKit 截图（屏幕外窗口两者都截不到→闪现展开补截） |
| StatusItemAX.swift | AX 命中检测/读标题/AXPress（v0.6.0 起实时枚举 AXExtrasMenuBar；偏好位置反查已移除，见坑 5.5） |
| ClickForwarder.swift | 合成 CGEvent 点击 / 合成 ⌘ 拖拽（常驻功能用） |
| CollectionPanel.swift | 下拉 NSPanel + SwiftUI 面板（搜索/排序/拖拽/键盘导航/悬停状态）+ 整理模式提示浮窗 |
| IconOrganizer.swift | 使用频率计数 + 三种排序模式（持久化到 UserDefaults） |
| HotkeyManager.swift | Carbon 全局热键 ⌃⌥H |

## 关键技术约束与坑（必读）

1. **macOS 26 Tahoe 菜单栏**：状态图标窗口全部由 Control Center 进程托管（ownerName/pid 无用）；窗口服务器把 10000pt 分隔条钳到 ~5016pt；菜单栏挤满时新图标被停在屏幕外（x≈-4220）并自动记住坏位置（所以启动时要钉住自己两个图标的位置）。
2. **macOS 27+ 不可用**：菜单栏重写为单窗口 + 系统 `«` 溢出，面板机制整体失效（代码里 legacyModel 分支处理，入口图标会提示）。
3. **TCC 授权与签名**：ad-hoc 签名每次编译都变 → 授权失效。已用自签证书 "NotchTray Dev" 解决（build.sh 直接尝试该证书签名，不要用 `security find-identity -v` 判断——未受信自签证书不会被列为 valid 但 codesign 能用）。build 时 `xattr -cr` 清扩展属性否则 codesign 报 "detritus" 错误。
4. **命名链**（匿名图标的名字来源，依次）：手动命名 > AX 标题(Title/Description/Value/Help，extras 树实时读、可离屏) → 窗口标题(kCGWindowName) → "未命名图标 N"（v0.6.0 起移除偏好位置反查，见 5.5）。必须过滤通用名：`Item-N`、空串、**"控制中心"/"Control Center"**（托管进程名会污染 AX 描述）。
5. **偏好位置反查的坐标系**：`NSStatusItem Preferred Position` 存的是**距右边缘距离**（值越大越靠左），不是绝对坐标！换算 `绝对x = screen.maxX - stored` 再匹配（容差 26pt）。苹果系域名（com.apple.*）和自己域名必须排除——Control Center 域里有一堆系统图标的位置，会造成假匹配。
5.5. **Tahoe 偏好位置数据只在 com.apple.controlcenter 一个域里**（实测全机扫描确认：第三方 App 自有域、沙盒容器均无 NSStatusItem 记录；CC 域的键名=窗口标题=存档名，坐标匹配无归属信息增量）。因此"偏好位置反查归属 App"在 Tahoe 上不可行，已移除（v0.6.0），匿名图标命名靠手动重命名。
6. **AX 按钮引用会失效**：Control Center 会重建 AX 树——这正是 v0.6.0 放弃缓存按钮、改为每次实时枚举 AXExtrasMenuBar 的原因（旧"失效作废、闪现重抓"机制已随重构移除）。
7. **统一日志抓不到 NSLog**：`log show` 查不到本应用输出（原因未明）。v0.6.0 起用 FileLog（`~/Library/Logs/NotchTray.log`）做可靠观测；也可前台跑二进制看 stderr：`./build/NotchTray.app/Contents/MacOS/NotchTray`。
8. **权限要求**：屏幕录制（截图图标窗口，授权后需重启 App）、辅助功能（AXPress/合成点击/⌘拖拽）。

## 已知问题（截至 v0.6.0）

- AXPress 的菜单锚定在停靠位置（屏幕外），菜单弹出位置可能异常——待用户实测反馈。
- AXExtrasMenuBar 匹配在多个图标停靠位置完全重合时按数组序兜底，可能按错（有日志可查）。
- 未命名图标需用户手动重命名（右键 → 重命名…），Tahoe 无公开归属数据可自动查。
- 点击兜底路径（实时 AXPress 未命中时）会展开菜单栏一次，属预期行为而非 bug；若某图标每次都走兜底，查 FileLog 定位匹配失败原因。
- 多屏场景未充分测试（面板定位/收起几何以主屏为准）。

## 待办 / 进行中

1. **图标定稿**：F1–F5 待选，F3 已改版为"刘海旁独立小盘"（预览见 build/icon-previews2/F3-swallow.png 与 scripts/preview_icons2.swift；F1/F2 致敬 Pinland/DockDoor，F4 躲进托盘，F5 迷你菜单栏；选定后用 scripts/make_icon.swift 改渲染逻辑 → 重新构建）。
2. **GitHub Release 挂 DMG**：用户手动上传最新 `dist/NotchTray-0.6.0.dmg`（https://github.com/NaiMaoOVO/NotchTray/releases）。
3. **用户验证 v0.6.0**：重命名是否解决命名问题、点击是否不再展开菜单栏。

功能方向（用户已定调：围绕图标本身的服务，**不做 to-do list**）：按频率自动收纳建议、多屏支持等（手动重命名已于 v0.6.0 完成）。

## 构建 / 发布流程

```bash
cd /Users/chenzixun/Documents/mac状态栏插件/NotchTray
# 改 Sources/*.swift 后：
# 1) Resources/Info.plist 里 CFBundleShortVersionString / CFBundleVersion 各 +1
./build.sh          # 编译 → 图标 → .app → 签名(NotchTray Dev) → DMG → 安装到 /Applications
open /Applications/NotchTray.app
# 2) 提交：git add -A && git commit && git push && git tag vX.Y.Z && git push origin vX.Y.Z
# 3) Release：dist/NotchTray-X.Y.Z.dmg 手动传 GitHub Releases（或用户提供 token）
```

注意：重新编译**不会**再掉权限授权（稳定签名）；但 Info.plist 的 CFBundleVersion 不递增的话，覆盖安装可能不生效。

## 与用户的约定

- 交接文档每轮必更（本文件）。
- 图标/交互类改动先出预览给用户挑。
- 提交信息用中文，描述"做了什么+为什么"。
