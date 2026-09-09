# 🛸 DJIToDrive (DJI 一键导入 Google Drive)

<p align="center">
  <img src="Resources/AppIcon.icns" width="128" height="128" alt="DJIToDrive Icon" />
</p>

<p align="center">
  <b>专为大疆（DJI）创作者打造的 macOS 原生极速云端自动同步中枢</b><br>
  完美支持 <b>Osmo Pocket 3 / 4</b>、<b>DJI 360 全景相机</b>、<b>Action 系列</b> 及主流 TF / SD 存储卡
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.10+-F05138?style=flat&logo=swift&logoColor=white" alt="Swift" />
  <img src="https://img.shields.io/badge/macOS-13.0+_Ventura+-000000?style=flat&logo=apple&logoColor=white" alt="macOS" />
  <img src="https://img.shields.io/badge/Google_Drive-Resumable_API_v3-4285F4?style=flat&logo=googledrive&logoColor=white" alt="Google Drive" />
  <img src="https://img.shields.io/badge/Architecture-SPM_Modular-blue?style=flat" alt="SPM" />
</p>

---

## ✨ 核心特性与亮点 (Key Features)

- 🔌 **即插即感，双存储堆叠感知 (Dual-Storage Perception)**
  - 接入相机或插卡瞬间毫秒级捕获（支持同时感知**机身内部存储**与**外置扩展 TF/SD 卡**）；
  - 自动识别 DJI 媒体盘，优先聚焦富媒体存储卷，零手动寻径。

- ⚡ **Google Drive 16MB Chunk 工业级断点续传 (Resumable Chunk Engine)**
  - 专为数十至数百 GB 的 4K/8K 巨幅全景与长视频优化；
  - 采用 16MB 分片安全断点切片，遇断网或重启自动接续，无需重传整个大文件；
  - 实时网速采样平滑算法与基于剩余传输量的动态精确剩余时间（ETA）推算。

- ☕ **系统级防休眠保护与屏幕息屏节能 (Sleep Assertion & Display Sleep)**
  - 基于 macOS 原生电源管理，长传期间自动阻止 Mac 系统睡眠（`PreventUserIdleSystemSleep`）；
  - **允许屏幕正常黑屏熄灭**，节能降温不伤屏，实现通宵挂机无人值守长传；
  - 传输完毕或暂停时秒级自动归还系统休眠控制权。

- 🛡️ **智能废片排查与伴随缓存清理 (Smart Junk Filter & Cascade Cleanup)**
  - 自动屏蔽 `.LRF` 低清代理视频与 `.THM` 缩略图；
  - 自动排查 0 字节损坏文件及小于设定阈值（如 <10MB）的误触废片；
  - **卡内物理空间释放**：已同步（✅）与废片素材支持单文件或一键批量彻底从相机存储卡删除，级联清除同名伴随缓存，秒释数百 GB 宝贵卡内容量。

- 🗂️ **按拍摄日期自动结构化归档 (Date-based Organization)**
  - 智能解析大疆专有命名（例如 `CAM_20260516142802_0001_D.OSV`）及拍摄时间戳；
  - 自动在云端创建并归档至 `目标目录/YYYY-MM-DD/`，素材条理井然。

- 🎯 **交互级队列调度与定宽对齐网格**
  - 单文件专属 `[⏸️ 暂停]` 让道与排队 #1 自动接力；
  - 支持紧急任务一键 `[⚡ 插队]` 优先推流；
  - 已同步与废片素材多阶梯沉底排序，顶部始终聚焦待传新素材。

- 🔐 **双轨凭据持久化与零密码打扰 (Zero-Prompt Authentication)**
  - 采用 POSIX `0600` 权限沙盒配置存储与安全刷新机制，彻底告别 macOS 钥匙串授权弹窗打扰，一次配置终生免调。

---

## 🏗️ 模块化系统架构 (Architecture)

本项目严格遵循 Swift 官方 Swift Package Manager (SPM) 模块化规范解耦构建，无任何臃肿第三方 CocoaPods / Carthage 依赖：

```
DJIToDrive/
├── Sources/
│   ├── DJIToDriveApp/      # macOS MenuBar 原生宿主、SwiftUI 控制面板与状态流
│   ├── DeviceDetector/     # POSIX 底层磁盘挂载事件监听与双卷感知
│   ├── MediaScanner/       # DJI 专有媒体识别、时间戳提取与废片过滤
│   ├── UploadEngine/       # 16MB Chunk 断点续传、调度队列与电源防休眠管理器
│   ├── AuthManager/        # Google OAuth 2.0 PKCE 授权与双轨凭据持久化
│   └── Ledger/             # 首尾 4MB SHA-256 极速指纹对账账本
├── Resources/              # Info.plist、Retina AppIcon.icns
└── scripts/
    └── package_app.sh      # 官方一键构建、组装 Bundle 与 Ad-hoc 签名脚本
```

---

## 🚀 快速上手与本地构建 (Quick Start)

### 运行环境要求
- **macOS**：macOS 13.0 (Ventura) 及以上版本
- **Xcode / Command Line Tools**：Swift 5.10 及以上

### 一键编译打包与运行
克隆项目后，在根目录直接运行自动化打包脚本：

```bash
# 1. 克隆代码仓库
git clone https://github.com/qljfjut/DJIToGoogleDrive.git
cd DJIToGoogleDrive

# 2. 一键编译并生成桌面应用程序
chmod +x scripts/package_app.sh
./scripts/package_app.sh
```

脚本将自动通过 SPM 编译 Release 版本，组装成原生 `DJIToDrive.app` 并部署到您的桌面上。双击打开即可静默常驻在右上角菜单栏！

---

## 🔒 隐私与安全性声明 (Privacy & Security)

- **纯本地运行**：本项目完全开源且纯本地运行，不设任何中转代理服务器；
- **凭据自主掌控**：Google Drive API 客户端凭据及 OAuth Access Token 仅在您的本地设备上安全存储，绝不回传任何第三方平台；
- **代码库零凭据污染**：Git 仓库内无任何硬编码密钥或用户私人数据。

---

## 📄 开源许可证 (License)

本项目基于 [MIT License](LICENSE) 开源。
