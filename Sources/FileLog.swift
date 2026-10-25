import Foundation

/// 轻量文件日志：~/Library/Logs/NotchTray.log
/// 统一日志抓不到本应用的 NSLog（原因未明），落盘文件是可靠的可观测手段。
/// 超过 1MB 自动截断。
enum FileLog {
    static let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/NotchTray.log")

    static func write(_ msg: String) {
        NSLog("%@", msg)
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64, size > 1_000_000 {
            try? data.write(to: url) // 截断重写
            return
        }
        if let fh = FileHandle(forWritingAtPath: url.path) {
            defer { try? fh.close() }
            fh.seekToEndOfFile()
            fh.write(data)
        } else {
            try? data.write(to: url)
        }
    }
}
