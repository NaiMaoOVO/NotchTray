// 生成 NotchTray 图标风格预览 v2（参照 Pinland / DockDoor 的设计语言：
// 深色底 + 浅色圆角卡片 + 大块面几何 + 俏皮拟物）。
// 用法: swift scripts/preview_icons2.swift   → build/icon-previews2/*.png

import AppKit

let S: CGFloat = 512
let outDir = "build/icon-previews2"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let bgBlack = NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.051, alpha: 1)
let cream = NSColor(calibratedRed: 0.945, green: 0.910, blue: 0.859, alpha: 1)
let inkDark = NSColor(calibratedRed: 0.125, green: 0.125, blue: 0.145, alpha: 1)
let tabRed = NSColor(calibratedRed: 0.882, green: 0.294, blue: 0.231, alpha: 1)
let tabBlue = NSColor(calibratedRed: 0.173, green: 0.373, blue: 0.878, alpha: 1)
let tabYellow = NSColor(calibratedRed: 0.965, green: 0.757, blue: 0.208, alpha: 1)
let tabGreen = NSColor(calibratedRed: 0.302, green: 0.753, blue: 0.420, alpha: 1)

func canvas() -> NSImage {
    let image = NSImage(size: NSSize(width: S, height: S))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    return image
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

func drawBase(_ img: NSImage, cardRect: NSRect? = nil, cardColors: [NSColor] = [cream, cream], cardAngle: CGFloat = -70) -> NSRect {
    let bgRect = NSRect(x: S * 0.02, y: S * 0.02, width: S * 0.96, height: S * 0.96)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: S * 0.215, yRadius: S * 0.215)
    bgBlack.setFill()
    bgPath.fill()

    let card = cardRect ?? NSRect(x: S * 0.24, y: S * 0.24, width: S * 0.52, height: S * 0.52)
    // 卡片投影，营造浮起感
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -S * 0.014)
    shadow.shadowBlurRadius = S * 0.03
    shadow.set()
    let cardPath = NSBezierPath(roundedRect: card, xRadius: S * 0.115, yRadius: S * 0.115)
    NSGradient(colors: cardColors)?.draw(in: cardPath, angle: cardAngle)
    NSGraphicsContext.restoreGraphicsState()
    return card
}

func rounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func dot(_ center: CGPoint, diameter: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                width: diameter, height: diameter)).fill()
}

// F1 · 致敬 Pinland：刘海横条下挂着三个彩色标签（图标被"挂"在刘海下）
do {
    let img = canvas()
    let card = drawBase(img)
    let barW = card.width * 0.66, barH = card.height * 0.21
    let barX = card.midX - barW / 2
    let barY = card.maxY - card.height * 0.10 - barH
    // 标签先画（顶部被横条盖住）；第一颗用绿色（奶油色会和卡片融为一体）
    let tabW = card.width * 0.155
    let tabs: [(NSColor, CGFloat)] = [(tabGreen, 0.42), (tabRed, 0.52), (tabBlue, 0.42)]
    let gap = card.width * 0.045
    let totalW = tabW * 3 + gap * 2
    var tx = card.midX - totalW / 2
    for (color, hRatio) in tabs {
        let tabH = card.height * hRatio
        let tabY = barY - tabH + barH * 0.55 // 顶边塞进横条后面
        rounded(NSRect(x: tx, y: tabY, width: tabW, height: tabH), radius: tabW * 0.5, color: color)
        tx += tabW + gap
    }
    // 刘海横条压在最上面
    rounded(NSRect(x: barX, y: barY, width: barW, height: barH), radius: barH * 0.55, color: inkDark)
    write(img, "F1-pinland")
}

// F2 · 致敬 DockDoor：软渐变卡片 + 笑脸，刘海条当"头发"
do {
    let img = canvas()
    let card = drawBase(img,
                        cardColors: [NSColor(calibratedRed: 0.992, green: 0.949, blue: 0.886, alpha: 1),
                                     NSColor(calibratedRed: 0.976, green: 0.831, blue: 0.741, alpha: 1),
                                     NSColor(calibratedRed: 0.851, green: 0.925, blue: 0.871, alpha: 1)],
                        cardAngle: -80)
    // 红绿灯点（窗口意象）
    let d = S * 0.032
    dot(CGPoint(x: card.minX + S * 0.075, y: card.maxY - S * 0.075), diameter: d, color: tabRed)
    dot(CGPoint(x: card.minX + S * 0.125, y: card.maxY - S * 0.075), diameter: d, color: tabYellow)
    dot(CGPoint(x: card.minX + S * 0.175, y: card.maxY - S * 0.075), diameter: d, color: tabGreen)
    // 刘海"头发"骑在卡片顶边
    let hairW = card.width * 0.52, hairH = S * 0.055
    rounded(NSRect(x: card.midX - hairW / 2, y: card.maxY - hairH * 0.45, width: hairW, height: hairH),
            radius: hairH * 0.5, color: inkDark)
    // 笑脸：眼、鼻、嘴
    let faceY = card.midY - card.height * 0.05
    dot(CGPoint(x: card.midX - card.width * 0.16, y: faceY + card.height * 0.10),
        diameter: S * 0.045, color: inkDark)
    dot(CGPoint(x: card.midX + card.width * 0.16, y: faceY + card.height * 0.10),
        diameter: S * 0.045, color: inkDark)
    // 鼻子：短竖胶囊（不与嘴相碰）
    rounded(NSRect(x: card.midX - S * 0.013, y: faceY - card.height * 0.015,
                   width: S * 0.026, height: card.height * 0.10),
            radius: S * 0.013, color: inkDark)
    // 微笑：下弯弧（∪），圆心在弧线上方
    let smile = NSBezierPath()
    smile.appendArc(withCenter: CGPoint(x: card.midX, y: faceY - card.height * 0.13),
                    radius: card.width * 0.19,
                    startAngle: 205, endAngle: 335, clockwise: false)
    smile.lineWidth = S * 0.026
    smile.lineCapStyle = .round
    inkDark.setStroke()
    smile.stroke()
    write(img, "F2-face")
}

// F3 · 原创演绎 · 刘海旁的独立收纳盘：刘海条 + 右侧一个独立的小插件盘，
// 彩点正从屏幕飞进盘里（强调"独立工具"，不是在刘海里整理）
do {
    let img = canvas()
    let card = drawBase(img)
    // 刘海条：卡片顶部中央
    let barW = card.width * 0.60, barH = card.height * 0.155
    let barY = card.maxY - card.height * 0.115 - barH
    rounded(NSRect(x: card.midX - barW / 2, y: barY, width: barW, height: barH),
            radius: barH * 0.55, color: inkDark)
    // 独立小盘：右下方，与刘海条明显分离
    let trayW = card.width * 0.38, trayH = card.height * 0.30
    let trayRect = NSRect(x: card.maxX - card.width * 0.105 - trayW,
                          y: card.minY + card.height * 0.115,
                          width: trayW, height: trayH)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -S * 0.008)
    shadow.shadowBlurRadius = S * 0.018
    shadow.set()
    rounded(trayRect, radius: trayH * 0.44, color: inkDark)
    NSGraphicsContext.restoreGraphicsState()
    // 盘里的三颗彩点
    let d = trayRect.height * 0.21
    for (i, color) in [tabRed, tabYellow, tabGreen].enumerated() {
        dot(CGPoint(x: trayRect.minX + trayW * (0.24 + CGFloat(i) * 0.26),
                    y: trayRect.midY), diameter: d, color: color)
    }
    // 一颗蓝点正从刘海方向飞进小盘（动势线：两个渐小的拖影）
    let flyY = (barY + trayRect.maxY) / 2
    dot(CGPoint(x: card.midX + card.width * 0.10, y: flyY), diameter: card.width * 0.105, color: tabBlue)
    dot(CGPoint(x: card.midX + card.width * 0.015, y: flyY + card.height * 0.035),
        diameter: card.width * 0.055, color: tabBlue.withAlphaComponent(0.45))
    // 左下角留白处补一颗小灰点（屏幕上"还在外面"的图标）
    dot(CGPoint(x: card.minX + card.width * 0.17, y: card.minY + card.height * 0.20),
        diameter: card.width * 0.075,
        color: NSColor(calibratedWhite: 0.55, alpha: 1))
    write(img, "F3-swallow")
}

// F4 · 原创演绎 · 躲进托盘：三个小图标方块探出托盘沿
do {
    let img = canvas()
    let card = drawBase(img)
    let trayW = card.width * 0.84, trayH = card.height * 0.20
    let trayRect = NSRect(x: card.midX - trayW / 2, y: card.minY + card.height * 0.14,
                          width: trayW, height: trayH)
    // 三个小图标方块，略微歪头，下半截藏在托盘后
    let sq = card.width * 0.21
    let squares: [(NSColor, CGFloat, CGFloat)] = [
        (tabRed, -0.10, -1), (tabBlue, 0.0, 0), (tabYellow, 0.10, 1),
    ]
    for (color, rotation, offset) in squares {
        let rect = NSRect(x: card.midX + CGFloat(offset) * sq * 1.28 - sq / 2,
                          y: trayRect.maxY - sq * 0.38,
                          width: sq, height: sq)
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: rotation * 180 / .pi)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        NSGraphicsContext.saveGraphicsState()
        transform.concat()
        rounded(rect, radius: sq * 0.28, color: color)
        // 方块里画一个小白点当"图标内容"
        dot(CGPoint(x: rect.midX, y: rect.midY + sq * 0.05), diameter: sq * 0.30,
            color: NSColor.white.withAlphaComponent(0.85))
        NSGraphicsContext.restoreGraphicsState()
    }
    // 托盘压住方块下半截
    rounded(trayRect, radius: trayH * 0.5, color: inkDark)
    write(img, "F4-peek")
}

// F5 · 原创演绎 · 迷你菜单栏：整条菜单栏装进图标，刘海在中央吞图标
do {
    let img = canvas()
    let bgRect = NSRect(x: S * 0.02, y: S * 0.02, width: S * 0.96, height: S * 0.96)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: S * 0.215, yRadius: S * 0.215)
    bgBlack.setFill()
    bgPath.fill()
    // 菜单栏条
    let barW = S * 0.78, barH = S * 0.20
    let barRect = NSRect(x: S * 0.5 - barW / 2, y: S * 0.5 - barH * 0.35, width: barW, height: barH)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
    shadow.shadowOffset = NSSize(width: 0, height: -S * 0.012)
    shadow.shadowBlurRadius = S * 0.026
    shadow.set()
    rounded(barRect, radius: barH * 0.5, color: cream)
    NSGraphicsContext.restoreGraphicsState()
    // 条上的图标圆点：左侧三颗彩色，右侧一颗灰
    let dd = barH * 0.30
    let dy = barRect.midY
    dot(CGPoint(x: barRect.minX + barW * 0.14, y: dy), diameter: dd, color: tabRed)
    dot(CGPoint(x: barRect.minX + barW * 0.24, y: dy), diameter: dd, color: tabBlue)
    dot(CGPoint(x: barRect.minX + barW * 0.34, y: dy), diameter: dd, color: tabGreen)
    dot(CGPoint(x: barRect.maxX - barW * 0.12, y: dy), diameter: dd,
        color: NSColor(calibratedWhite: 0.45, alpha: 1))
    // 刘海块从条顶部长出来，吞掉中间一颗点（半截可见）
    let notchW = barW * 0.24, notchH = barH * 0.85
    dot(CGPoint(x: barRect.midX + notchW * 0.62, y: dy), diameter: dd, color: tabYellow) // 即将被吞
    let notchRect = NSRect(x: barRect.midX - notchW / 2, y: barRect.maxY - notchH * 0.62,
                           width: notchW, height: notchH)
    rounded(notchRect, radius: notchH * 0.45, color: inkDark)
    write(img, "F5-menubar")
}
