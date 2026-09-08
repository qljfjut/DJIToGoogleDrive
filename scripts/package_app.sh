#!/usr/bin/env bash
# ====================================
# 📁 脚本职责：DJIToDrive 官方发布打包与桌面应用生成脚本
# 包含：SPM release 编译、多分辨率 Retina 图标转换、.app 结构封装与原生代码重签名
# 依赖：swift, sips, iconutil, codesign, xattr
# ====================================

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_SRC="/Users/qianliangjun/.gemini/antigravity/brain/5a3ec9d4-0fa9-4f2a-95e0-13c27fe194c4/dji_drive_icon_1788877977561.jpg"
APP_NAME="DJIToDrive"
BUNDLE_DIR="$PROJECT_ROOT/$APP_NAME.app"
DESKTOP_DIR="/Users/qianliangjun/Desktop"

echo "🔨 步骤 1/4: 使用 SPM 官方工具链编译 Release 版本..."
cd "$PROJECT_ROOT"
swift build -c release

# 查找生成的二进制文件
BIN_PATH=""
if [ -f "$PROJECT_ROOT/.build/release/DJIToDriveApp" ]; then
    BIN_PATH="$PROJECT_ROOT/.build/release/DJIToDriveApp"
elif [ -f "$PROJECT_ROOT/.build/arm64-apple-macosx/release/DJIToDriveApp" ]; then
    BIN_PATH="$PROJECT_ROOT/.build/arm64-apple-macosx/release/DJIToDriveApp"
else
    BIN_PATH=$(find "$PROJECT_ROOT/.build" -name "DJIToDriveApp" -type f -perm +111 | head -n 1)
fi

if [ -z "$BIN_PATH" ] || [ ! -f "$BIN_PATH" ]; then
    echo "❌ 未找到编译生成的可执行文件！"
    exit 1
fi
echo "✅ 找到二进制：$BIN_PATH"

echo "🎨 步骤 2/4: 生成 macOS 专属 AppIcon.icns (Retina 多分辨率标准)..."
ICONSET_DIR="$PROJECT_ROOT/.build/AppIcon.iconset"
BASE_PNG="$PROJECT_ROOT/.build/base_icon.png"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sips -s format png "$ICON_SRC" --out "$BASE_PNG" >/dev/null 2>&1

sips -z 16 16     "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null 2>&1
sips -z 32 32     "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null 2>&1
sips -z 32 32     "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null 2>&1
sips -z 64 64     "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null 2>&1
sips -z 128 128   "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null 2>&1
sips -z 256 256   "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1
sips -z 256 256   "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null 2>&1
sips -z 512 512   "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1
sips -z 512 512   "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null 2>&1
sips -z 1024 1024 "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null 2>&1

mkdir -p "$PROJECT_ROOT/Resources"
iconutil -c icns "$ICONSET_DIR" -o "$PROJECT_ROOT/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR"
echo "✅ AppIcon.icns 生成完毕"

echo "📦 步骤 3/4: 组装 macOS Application Bundle ($APP_NAME.app)..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$BIN_PATH" "$BUNDLE_DIR/Contents/MacOS/DJIToDriveApp"
chmod +x "$BUNDLE_DIR/Contents/MacOS/DJIToDriveApp"

cp "$PROJECT_ROOT/Resources/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
echo "APPL????" > "$BUNDLE_DIR/Contents/PkgInfo"

echo "🛡️ 步骤 3.5: 清除隔离属性并执行 macOS 原生 Ad-hoc 代码重签名..."
xattr -cr "$BUNDLE_DIR"
codesign --force --deep --sign - "$BUNDLE_DIR"

echo "🚀 步骤 4/4: 发布至桌面并同步签名与刷新缓存..."
rm -rf "$DESKTOP_DIR/$APP_NAME.app"
cp -R "$BUNDLE_DIR" "$DESKTOP_DIR/$APP_NAME.app"
xattr -cr "$DESKTOP_DIR/$APP_NAME.app"
codesign --force --deep --sign - "$DESKTOP_DIR/$APP_NAME.app"
touch "$DESKTOP_DIR/$APP_NAME.app"

echo "🎉 打包完成！您可以在桌面上直接双击打开【$APP_NAME.app】，启动后将自动弹出控制台！"
