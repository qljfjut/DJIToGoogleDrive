#!/usr/bin/env bash
# ====================================
# 📁 脚本职责：DJIToGoogleDrive 官方发布打包与桌面应用生成脚本
# 包含：SPM release 编译、多分辨率 Retina 图标转换、.app 结构封装与原生代码重签名
# 依赖：swift, sips, iconutil, codesign, xattr
# ====================================

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_SRC="$PROJECT_ROOT/Resources/AppIcon.png"
APP_NAME="DJIToGoogleDrive"
BUNDLE_DIR="$PROJECT_ROOT/.build/$APP_NAME.app"
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
if [ -f "$PROJECT_ROOT/CHANGELOG.md" ]; then
    cp "$PROJECT_ROOT/CHANGELOG.md" "$BUNDLE_DIR/Contents/Resources/CHANGELOG.md"
fi
echo "APPL????" > "$BUNDLE_DIR/Contents/PkgInfo"

echo "🛡️ 步骤 3.5: 清除隔离属性并执行 macOS 原生 Ad-hoc 代码重签名..."
xattr -cr "$BUNDLE_DIR"
codesign --force --deep --sign - "$BUNDLE_DIR"

echo "🚀 步骤 4/4: 发布至 /Applications 并同步签名与刷新缓存..."
rm -rf "/Applications/$APP_NAME.app"
cp -R "$BUNDLE_DIR" "/Applications/$APP_NAME.app"
xattr -cr "/Applications/$APP_NAME.app"
codesign --force --deep --sign - "/Applications/$APP_NAME.app"
touch "/Applications/$APP_NAME.app"

# 彻底清理桌面与工作区裸包，杜绝 macOS Launch Services 抓取双图标
rm -rf "$DESKTOP_DIR/$APP_NAME.app"
rm -rf "$PROJECT_ROOT/$APP_NAME.app"

# 从 macOS Launch Services 注销非 /Applications 的一切历史与幽灵注册项
LS_REGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -f "$LS_REGISTER" ]; then
    "$LS_REGISTER" -u "$PROJECT_ROOT/$APP_NAME.app" 2>/dev/null || true
    "$LS_REGISTER" -u "$DESKTOP_DIR/$APP_NAME.app" 2>/dev/null || true
    "$LS_REGISTER" -u "$BUNDLE_DIR" 2>/dev/null || true
    "$LS_REGISTER" -f "/Applications/$APP_NAME.app" 2>/dev/null || true
fi

echo "🎉 打包完成！【$APP_NAME.app】已独家更新部署至 /Applications，并完成 Apple 原生签名与启动台单一化注册！"
