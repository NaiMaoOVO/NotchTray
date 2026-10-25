#!/bin/bash
# NotchTray 构建脚本：无需 Xcode，只用 Swift 命令行工具（swiftc）。
# 产出: build/NotchTray.app 和 dist/NotchTray-<版本>.dmg
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(defaults read "$(pwd)/Resources/Info.plist" CFBundleShortVersionString)
echo "==> 版本 $VERSION"

echo "==> 编译 Swift 源码"
mkdir -p build
# 部署目标 14.0：CGWindowListCreateImage 在 macOS 15 头文件中被标记废弃，
# 目标 ≥15 时直接不可编译；14 下只是弃用警告，运行时授权后仍可用
swiftc -O -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -o build/NotchTray \
  Sources/*.swift

echo "==> 生成 App 图标"
if [ ! -f Resources/AppIcon.icns ]; then
  swift scripts/make_icon.swift build
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

echo "==> 组装 .app"
APP=build/NotchTray.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/NotchTray "$APP/Contents/MacOS/NotchTray"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> 签名（稳定身份：TCC 授权在重新编译后依然有效）"
xattr -cr "$APP"
# 注意：不能用 security find-identity -v 判断——未受信的自签证书不会被列为 valid，
# 但 codesign 能正常使用它。直接签名，失败才退回 ad-hoc
if codesign --force --sign "NotchTray Dev" "$APP" 2>/dev/null; then
  echo "    已用 NotchTray Dev 证书签名"
else
  echo "    （NotchTray Dev 证书不可用，退回 ad-hoc——重新编译会使权限授权失效）"
  codesign --force --sign - "$APP"
fi

echo "==> 打包 DMG"
mkdir -p dist
rm -f "dist/NotchTray-$VERSION.dmg"
hdiutil create -volname "NotchTray" -srcfolder "$APP" -ov -format UDZO "dist/NotchTray-$VERSION.dmg" -quiet

echo "==> 安装到 /Applications（启动台可见；先优雅退出运行中的实例）"
osascript -e 'tell application id "local.notchtray" to quit' >/dev/null 2>&1 || true
sleep 1
ditto "$APP" /Applications/NotchTray.app

echo "==> 完成:"
echo "    $APP"
echo "    dist/NotchTray-$VERSION.dmg"
echo "    /Applications/NotchTray.app"
