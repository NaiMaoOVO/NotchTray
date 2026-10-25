// 生成 NotchTray 的 App 图标：圆角渐变底 + 白色 tray.full 符号。
// 用法: swift scripts/make_icon.swift <输出目录>
// 产出 AppIcon.iconset/，再用 iconutil 转 .icns（build.sh 自动做）。

import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func renderBase() -> NSImage {
    let s: CGFloat = 1024
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let bgRect = NSRect(x: s * 0.02, y: s * 0.02, width: s * 0.96, height: s * 0.96)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.215, yRadius: s * 0.215)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.23, green: 0.56, blue: 0.98, alpha: 1),
                              ending: NSColor(calibratedRed: 0.05, green: 0.26, blue: 0.62, alpha: 1))
    gradient?.draw(in: bgPath, angle: -70)

    if let base = NSImage(systemSymbolName: "tray.full", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .regular)
        if let symbol = base.withSymbolConfiguration(config) {
            // 模板符号是黑色，用 sourceAtop 染成白色
            let tinted = NSImage(size: symbol.size)
            tinted.lockFocus()
            symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
            NSColor.white.set()
            NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            let iconSide = s * 0.58
            let drawRect = NSRect(x: (s - iconSide) / 2, y: (s - iconSide) / 2 - s * 0.02,
                                  width: iconSide, height: iconSide)
            tinted.draw(in: drawRect)
        }
    }
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to path: String, pixels: Int) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: URL(fileURLWithPath: path))
}

let iconsetDir = outDir.hasSuffix(".iconset") ? outDir : (outDir as NSString).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let base = renderBase()
let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in entries {
    try writePNG(base, to: (iconsetDir as NSString).appendingPathComponent("\(name).png"), pixels: px)
}
print("iconset written to \(iconsetDir)")
