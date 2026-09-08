# 📋 DJIToDrive 跨账号全景交接底座 (Project Handoff & Continuity Base)

> 📌 **项目版本**：`v0.1.0-genesis` | 📅 **最后更新时间**：`2026-09-08 22:15` | 🏷️ **当前状态**：`Day-0 基础设施就绪`

---

## 1. 🌱 项目从 0 到 1 演进史与架构决策 (Genesis & Architectural Decisions)
- **项目起源**：创作者拥有 DJI 360 全景相机、Pocket 3、Pocket 4，日常产出海量 4K/8K 与 360 全景巨型视频，需要一套插入 Mac 即可一键/半自动将素材增量同步至 Google Drive 的高可靠工具。
- **关键技术选型抉择**：
  1. **放弃 Electron / Web 技术栈**：坚决采用 Swift + SwiftUI 原生 macOS 开发，确保常驻菜单栏资源占用极小（轻量级无感后台），并能无缝调用 `NSWorkspace` 硬件卷盘挂载通知与系统 Keychain。
  2. **放弃混合 Python / Rclone 外挂**：采用全栈纯原生 `URLSession` 实现 Google Drive Resumable Upload 协议，零外部二进制分发负担，体积小巧可打包为独立原生 DMG。
  3. **大视频去重算法抉择**：针对动辄 20GB+ 的 360 全景素材，摒弃全盘 SHA-256（会导致卡死 CPU），采用 `首4MB + 尾4MB + 字节总长` 的复合高阶指纹算法，毫秒级比对。

---

## 2. 💬 近期对话上下文与用户意图快照 (Context Snapshot)
- **硬件矩阵**：用户确认拥有 **DJI 360 全景相机**、**Osmo Pocket 3**、**Osmo Pocket 4**。
- **物理接口**：支持 **高速读卡器插 TF/SD 卡** 与 **Type-C 数据线直连设备挂载** 两种场景。
- **文件过滤意图**：
  - 强制丢弃 `.LRF`（低码率代理）与 `.THM`（缩略图），节省网盘配额；
  - 完整保留 Pocket 3 外接 DJI Mic 2 录制的 `.WAV` 独立音轨文件与 `.SRT` 飞控字幕。
- **交互偏好**：半自动模式（设备插入后 Mac 弹出气泡通知，点击进入审查窗口，默认全选，一键确认上传）。

---

## 3. 🎯 运行环境与底层设施 (Runtime & Environment)
- **开发系统**：macOS 14+ (Sonoma) / macOS 15+ (Sequoia)
- **开发工具链**：Xcode 15+ / Swift 5.10+，使用 Swift Package Manager 现代增量工具链构建。
- **云端服务**：Google Drive REST API v3（Resumable Chunked Upload 模式，支持 16MB Chunk 断点续传）。
- **本地安全**：macOS Keychain (`Security.framework`) 托管 OAuth Token。

---

## 4. 🧠 业务模型与核心映射表 (Business Models & Mappings)
- **白名单后缀**：`.mp4`, `.mov`, `.dng`, `.jpg`, `.jpeg`, `.wav`, `.srt`
- **黑名单后缀**：`.lrf`, `.thm`, `._*`, `.DS_Store`, `.Trashes`
- **云端目标路径生成公式**：
  `DJI_Media/{YYYY-MM-DD}/{OriginalFileName}`
- **分片大小**：
  `16 * 1024 * 1024` bytes (16MB，符合 Google 256KB 整数倍要求)

---

## 5. 🗺️ 核心代码地图 (Code Map - SPM Blueprint)

```
DJIToDrive/
├── Package.swift               # SPM 官方工程包定义
├── Sources/
│   ├── DJIToDriveApp/         # MenuBar 主入口与 UI 生命周期
│   ├── DeviceDetector/        # 卷盘挂载监听与设备特征比对
│   ├── MediaScanner/          # DCIM 目录遍历与文件白黑名单过滤
│   ├── UploadEngine/          # URLSession 分片断点续传器与会话管理
│   ├── AuthManager/           # Google OAuth 2.0 PKCE 鉴权与 Keychain
│   └── Ledger/                # 本地 SHA-256 去重账本 (JSON/SQLite)
└── Tests/
    ├── DeviceDetectorTests/   # 设备特征识别单元测试
    ├── MediaScannerTests/     # 过滤逻辑单元测试
    └── UploadEngineTests/     # 分片计算与 Mock 传输测试
```

---

## 6. 🚦 当前进度与优先级路线图 (Progress & Roadmap)
- `[已完成]` Day-0 规划文档与创世五件套初始化；
- `[已完成]` P1 阶段：初始化 SPM 官方工程包，构建 MenuBar 原生骨架，设计专属 Retina 图标并解决代码签名与桌面发布；
- `[已完成]` P2 阶段：实现 `DeviceDetector` 物理卷盘热插拔感知与 `MediaScanner` 白黑名单过滤引擎（保留 `.WAV`/`.SRT`，过滤 `.LRF`）；
- `[已完成]` P3 阶段：实现 `AuthManager`（OAuth 2.0 PKCE + Keychain 凭证安全托管）与 `UploadEngine`（16MB Chunk 断点续传 + 首尾 4MB 去重账本）；
- `[P4 待办]` 接入真实 Google Drive 凭据联调测试，进行模拟大文件上云实测并制作正式发布版 DMG 安装包。

---

### 💬 新 AI 接力唤醒提示词 (Next AI Prompt)
> "我是新接手的架构师。已通读 `HANDOFF.md`、`ARCHITECTURE.md` 与 `BUSINESS_RULES.md`。当前 P1、P2、P3 核心引擎已全量贯通上线并在桌面运行，请协助用户录入 Google Cloud 凭证并推进 P4 实测与发布打包！"
