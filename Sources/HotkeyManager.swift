// 全局热键 ⌃⌥H（Carbon 是无第三方依赖实现系统级热键的唯一途径）。
// 基于 menubar-hide (github.com/junior-rj/menubar-hide, MIT) 的实现改编，见 README 致谢。

import Carbon.HIToolbox

@MainActor
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onToggle: () -> Void
    private(set) var isRegistered = false

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            // Carbon 在主 run loop 上回调
            MainActor.assumeIsolated {
                Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue().onToggle()
            }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
        guard handlerStatus == noErr, handlerRef != nil else {
            NSLog("notchtray: hotkey handler installation failed (status \(handlerStatus))")
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E54_5259), id: 1) // 'NTRY'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey),
                                         hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr || hotKeyRef == nil {
            NSLog("notchtray: hotkey registration failed (status \(status)) — ⌃⌥H 可能被占用")
            return
        }
        isRegistered = true
    }
}
