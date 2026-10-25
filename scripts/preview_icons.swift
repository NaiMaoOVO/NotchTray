// 生成 5 版 App 图标风格预览 PNG（512px），输出到 build/icon-previews/。
// 用法: swift scripts/preview_icons.swift

import AppKit

let S: CGFloat = 512
let outDir = "build/icon-previews"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func canvas() -> NSImage {
    let image = NSImage(size: NSSize(width: S, height: S))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    return image
}

func roundedBG(_ rect: NSRect, radius: CGFloat, colors: [NSColor], angle: CGFloat = -70) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(colors: colors)?.draw(in: path, angle: angle)
}

func tintedSymbol(_ name: String, color: NSColor, pointSize: CGFloat) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    guard let symbol = base.withSymbolConfiguration(config) else { return nil }
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
    color.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    return tinted
}

func write(_ image: NSImage, _ name: String) {
    image.unlockFocus()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: S, height: S), from: NSRect(origin: .zero, size: image.size),
               operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("wrote \(outDir)/\(name).png")
}

let bgRect = NSRect(x: S * 0.02, y: S * 0.02, width: S * 0.96, height: S * 0.96)
let radius = S * 0.215

// A · 蓝渐变托盘（现状版，对照）
do {
    let img = canvas()
    roundedBG(bgRect, radius: radius,
              colors: [NSColor(calibratedRed: 0.23, green: 0.56, blue: 0.98, alpha: 1),
                       NSColor(calibratedRed: 0.05, green: 0.26, blue: 0.62, alpha: 1)])
    if let sym = tintedSymbol("tray.full", color: .white, pointSize: S * 0.5) {
        let side = S * 0.58
        sym.draw(in: NSRect(x: (S - side) / 2, y: (S - side) / 2 - S * 0.02, width: side, height: side))
    }
    write(img, "A-blue-tray")
}

// B · 墨黑极简（macOS 系统工具风）
do {
    let img = canvas()
    roundedBG(bgRect, radius: radius,
              colors: [NSColor(white: 0.11, alpha: 1), NSColor(white: 0.18, alpha: 1)])
    let path = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
    path.lineWidth = S * 0.012
    NSColor(white: 1, alpha: 0.16).setStroke()
    path.stroke()
    if let sym = tintedSymbol("tray.full", color: .white, pointSize: S * 0.46) {
        let side = S * 0.5
        sym.draw(in: NSRect(x: (S - side) / 2, y: (S - side) / 2, width: side, height: side))
    }
    write(img, "B-dark")
}

// C · 刘海概念（图标即产品故事：顶部刘海 + 蓝色托盘收纳）
do {
    let img = canvas()
    roundedBG(bgRect, radius: radius,
              colors: [NSColor(white: 0.98, alpha: 1), NSColor(white: 0.90, alpha: 1)])
    // 顶部中央"刘海"黑块
    let notchW = S * 0.46, notchH = S * 0.15
    let notchRect = NSRect(x: (S - notchW) / 2, y: bgRect.maxY - notchH, width: notchW, height: notchH)
    let notchPath = NSBezierPath(roundedRect: notchRect, xRadius: S * 0.045, yRadius: S * 0.045)
    NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
    notchPath.fill()
    if let sym = tintedSymbol("tray.2", color: NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.95, alpha: 1),
                              pointSize: S * 0.40) {
        let side = S * 0.44
        let availableTop = bgRect.maxY - notchH
        let y = bgRect.minY + (availableTop - bgRect.minY - side) / 2
        sym.draw(in: NSRect(x: (S - side) / 2, y: y, width: side, height: side))
    }
    write(img, "C-notch")
}

// D · 暖橙收纳（tray.and.arrow.down，动作感）
do {
    let img = canvas()
    roundedBG(bgRect, radius: radius,
              colors: [NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.22, alpha: 1),
                       NSColor(calibratedRed: 0.91, green: 0.31, blue: 0.11, alpha: 1)],
              angle: -60)
    if let sym = tintedSymbol("tray.and.arrow.down", color: .white, pointSize: S * 0.46) {
        let side = S * 0.56
        sym.draw(in: NSRect(x: (S - side) / 2, y: (S - side) / 2 - S * 0.01, width: side, height: side))
    }
    write(img, "D-orange")
}

// E · 玻璃点阵（Tahoe 浅色玻璃 + 彩点入托盘的抽象隐喻）
do {
    let img = canvas()
    roundedBG(bgRect, radius: radius,
              colors: [NSColor(calibratedRed: 0.89, green: 0.93, blue: 0.99, alpha: 1),
                       NSColor(calibratedRed: 0.74, green: 0.84, blue: 0.97, alpha: 1)],
              angle: -80)
    // 顶部高光层（玻璃感）
    let hl = NSBezierPath(roundedRect: bgRect.insetBy(dx: S * 0.028, dy: S * 0.028),
                          xRadius: S * 0.19, yRadius: S * 0.19)
    NSColor(white: 1, alpha: 0.38).setFill()
    hl.fill()
    // 托盘：深灰蓝粗条
    let trayRect = NSRect(x: S * 0.26, y: S * 0.26, width: S * 0.48, height: S * 0.07)
    let tray = NSBezierPath(roundedRect: trayRect, xRadius: S * 0.035, yRadius: S * 0.035)
    NSColor(calibratedRed: 0.24, green: 0.31, blue: 0.41, alpha: 1).setFill()
    tray.fill()
    // 三个彩点正在落入托盘
    let dotColors: [NSColor] = [
        NSColor(calibratedRed: 0.85, green: 0.20, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.15, green: 0.47, blue: 0.91, alpha: 1),
        NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.07, alpha: 1),
    ]
    let d = S * 0.14
    for (i, color) in dotColors.enumerated() {
        let x = S * 0.5 - d / 2 + CGFloat(i - 1) * S * 0.165
        let y = S * 0.26 + S * 0.07 + S * 0.075 + CGFloat(abs(1 - i)) * S * 0.0
        let dot = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: d, height: d))
        color.setFill()
        dot.fill()
    }
    write(img, "E-glass")
}
