# 📦 DJIToGoogleDrive - GitHub 发布历史与归档中枢 (Releases Archive Center)

> 📌 本目录专门用于对接 **GitHub Releases**，按正式发版版本号物理分级归档历史产物、发布说明文案与安全校验码。

---

## 🗺️ 版本归档地图 (Version Catalog)

| 版本号 | 发布日期 | 核心里程碑特性 | 归档资产状态 |
| :---: | :---: | :--- | :---: |
| [**v1.2.2**](./v1.2.2/) | 2026-09-10 | 启动台双图标根治(隐身打包)、偏好设置层级重构、更新亮点按需折叠、语言独立通栏防截断、去重去噪 | ✅ App包 + 源码包 + SHA256 |
| [**v1.2.1**](./v1.2.1/) | 2026-09-10 | 502探针自愈、大疆官方学名(Osmo 360)、SN设备号读取、即插即报横幅、App内一键自更新 | ✅ App包 + 源码包 + SHA256 |
| [**v1.2.0**](./v1.2.0/) | 2026-09-09 | 品牌重命名为 DJIToGoogleDrive、原生双语国际化 (i18n)、我有神器生态联动 | ✅ App包 + 源码包 + SHA256 |
| [**v1.1.0**](./v1.1.0/) | 2026-09-09 | 界面垂直裁切修复 (645pt)、图标永久常驻、系统防休眠与息屏节能 | ✅ 发布日志已归档 |
| [**v1.0.0**](./v1.0.0/) | 2026-09-08 | 创世首版：双存储感知、Google Drive 16MB Chunk 断点续传、Keychain安全存储 | ✅ 发布日志已归档 |

---

## 🚀 GitHub Releases 极速发布 3 步指南 (Release SOP)

当需要向 GitHub 发布或更新 Release 时，按以下极速流水线操作：

1. **打开 GitHub Releases 发布页**：
   - 访问 `https://github.com/qljfjut/DJIToGoogleDrive/releases/new`
2. **选择 Tag 与填写标题**：
   - **Tag**: 输入版本号（例如 `v1.2.0`）并点击回车创建；
   - **Title**: 输入对应发布标题（例如 `DJIToGoogleDrive v1.2.0 官方正式发布版`）；
3. **复制文案并拖入安装包**：
   - 打开对应版本文件夹（例如 `Github发布存档/v1.2.0/`）；
   - 将 `RELEASE_NOTES.md` 的内容全选复制，粘贴到 GitHub 的 **Describe this release** 输入框；
   - 将 `DJIToGoogleDrive-v1.2.0-macOS.zip` 直接拖入下方的 **Attach binaries** 虚线框；
   - 点击 **Publish release**，发布完成！

---

## 🛠️ 新版本自动归档指令

未来若需发布新版本（例如 `v1.3.0`），直接在项目根目录运行自动化脚本：

```bash
chmod +x scripts/archive_release.sh
./scripts/archive_release.sh v1.3.0
```

脚本将自动执行 SPM Release 编译、原生 Ad-hoc 重签名、打包 App Zip 与源码 Zip、计算 SHA-256 校验和并自动生成归档目录！
