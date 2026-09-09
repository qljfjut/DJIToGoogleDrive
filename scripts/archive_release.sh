#!/usr/bin/env bash
# ====================================
# 📁 脚本职责：自动化 GitHub Releases 打包归档流水线
# 包含：版本号探测、Release 编译、ditto 无损打包、源码归档、SHA256 生成与目录整理
# 依赖：bash, swift, ditto, shasum, zip
# ====================================

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-v1.2.0}"

# 统一版本号格式（确保带 v 前缀）
if [[ ! "$VERSION" =~ ^v ]]; then
    VERSION="v$VERSION"
fi

echo "🚀 [1/5] 开始执行 $VERSION 版本自动化发布归档流水线..."
cd "$PROJECT_ROOT"

# 1. 确保最新 Release 版本编译并打包完毕
echo "🔨 [2/5] 调用 package_app.sh 编译并封装最新应用..."
./scripts/package_app.sh

APP_PATH="$PROJECT_ROOT/DJIToGoogleDrive.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 未找到 $APP_PATH，打包终止！"
    exit 1
fi

# 2. 建立版本归档目标目录
ARCHIVE_DIR="$PROJECT_ROOT/Github发布存档/$VERSION"
mkdir -p "$ARCHIVE_DIR"
echo "📂 [3/5] 归档目录就绪: $ARCHIVE_DIR"

# 3. 使用 macOS 原生 ditto 打包二进制 App（保留签名与权限）
RELEASE_ZIP="$ARCHIVE_DIR/DJIToGoogleDrive-$VERSION-macOS.zip"
echo "🗜️ [4/5] 正在生成应用安装包: $(basename "$RELEASE_ZIP")..."
rm -f "$RELEASE_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$RELEASE_ZIP"

# 4. 打包纯净源码包
SOURCE_ZIP="$ARCHIVE_DIR/DJIToGoogleDrive-$VERSION-Source.zip"
echo "📦 [4.5/5] 正在生成纯净源码包: $(basename "$SOURCE_ZIP")..."
rm -f "$SOURCE_ZIP"
zip -r "$SOURCE_ZIP" \
  Package.swift Sources Resources scripts ARCHITECTURE.md BUSINESS_RULES.md README.md README_zh.md LICENSE .gitignore \
  -x "*.DS_Store" "*__MACOSX*" >/dev/null 2>&1

# 5. 生成 SHA-256 安全哈希校验文件
echo "🔐 [5/5] 正在计算 SHA-256 安全哈希校验码..."
cd "$ARCHIVE_DIR"
shasum -a 256 *.zip > SHA256SUMS.txt

echo ""
echo "🎉 ===================================================================="
echo "🎉 $VERSION 版本归档全量完成！"
echo "📂 归档目录：$ARCHIVE_DIR"
echo "📄 包含文件："
ls -lh "$ARCHIVE_DIR"
echo "🎉 ===================================================================="
