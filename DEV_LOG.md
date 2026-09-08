# 📝 DJIToDrive 开发与审计编年史 (Development Audit Log)

所有代码、配置与架构变更必须在完成编写后在此追加记录，保持可回溯的审计链。

---

### 📅 [2026-09-08 22:15] 项目创世初始化 (Day-0 Genesis)
- **操作类型**：`[新增]`
- **涉及文件**：
  - `ARCHITECTURE.md`（新增）
  - `BUSINESS_RULES.md`（新增）
  - `GEMINI.md`（新增）
  - `DEV_LOG.md`（新增）
  - `HANDOFF.md`（新增）
  - `.gitignore`（新增）
- **改动背景与原理**：
  - 用户启动新项目，确认核心需求为 macOS 原生图形界面程序（MenuBar App），实现 DJI 360 全景相机、Pocket 3/4 等设备一键导入 Google Drive。
  - 完成背景与技术选型访谈，确定纯原生 Swift/SwiftUI 方案，使用 `URLSession` 实现 16MB Chunk 断点续传，集成 Google OAuth 2.0 PKCE 与 macOS Keychain。
  - 执行全局规范第九条/第十条强制规划与第八条「五件套创世初始化」，固化业务规约与架构标准，建立 Day-0 Git 安全回滚原点。
- **主要改动细节**：
  1. 建立 `ARCHITECTURE.md`，定义 SPM 模块化划分、单文件≤800行上限、AI 注释头及官方构建工具链令。
  2. 建立 `BUSINESS_RULES.md`，确立 Pocket 3/4 与 360 全景设备识别特征、媒体文件白黑名单（过滤 `.LRF`/`.THM`，保留 `.WAV`/`.SRT`）、首尾 4MB 哈希去重账本及云端 `DJI_Media/{YYYY-MM-DD}/` 归档结构。
  3. 建立 `GEMINI.md`，固化物理死锁隔离、Keychain 安全托管与规范约束。
  4. 建立 `.gitignore` 与 `HANDOFF.md`，锁定 Day-0 初始化状态。
- **验证结果**：规划文档与基础设施就绪，Git 创世提交即将生成。
---

### 📅 [2026-09-08 22:36] P1 阶段达成：MenuBar 原生应用骨架与桌面专属图标打包发布
- **操作类型**：`[新增]` / `[修复]`
- **涉及文件**：
  - `Package.swift`（新增）
  - `Sources/DJIToDriveApp/AppMain.swift`（新增）
  - `Sources/DJIToDriveApp/AppDelegate.swift`（新增）
  - `Sources/DJIToDriveApp/MenuBarView.swift`（新增）
  - `Resources/Info.plist`（新增）
  - `scripts/package_app.sh`（新增）
  - `.gitignore`（修改）
- **改动背景与原理**：
  - 落实 P1 路线图，建立基于 SPM 的 macOS 原生工程，构建常驻顶部菜单栏的 StatusItem 与 SwiftUI 控制面板原型。
  - 按照用户指示生成可视化应用图标与桌面可双击运行的应用包（`.app`），解决 Swift 6 严格并发 `@MainActor` 顶层隔离限制与 `sips`/`iconutil` 格式生成流水线。
- **主要改动细节**：
  1. 升级入口为 `@main struct DJIToDriveApp`，显式标注 `@MainActor` 调度主循环，消除 Actor 隔离警告。
  2. 设计生成融合 DJI 镜头光圈与 Google Drive 三角配色的 macOS Squircle 高清专属图标，并转码为符合 Apple Retina 规范的多分辨率 `AppIcon.icns`。
  3. 配置 `Info.plist`（注入 `LSUIElement=true` 菜单栏常驻元数据），编写 `package_app.sh` 组装原生应用包并自动发布到桌面。
- **验证结果**：`swift build -c release` 构建耗时 0.10s 成功，`/Users/qianliangjun/Desktop/DJIToDrive.app` 已生成并刷新图标，双击可直接拉起常驻菜单栏。
---

### 📅 [2026-09-08 23:38] 启动故障修复与 P2 硬件感知模块正式交付
- **操作类型**：`[修复]` / `[新增]`
- **涉及文件**：
  - `Sources/DeviceDetector/DeviceDetector.swift`（修改：修复 Swift 6 deinit 非隔离与 Task 主线程派发）
  - `Sources/DJIToDriveApp/AppDelegate.swift`（修改：注入启动 0.3s 主动展开反馈，设置兼容相机图标）
  - `scripts/package_app.sh`（修改：打包注入 `xattr -cr` 与 `codesign --force --deep --sign -` 签名）
  - `DEV_LOG.md`（修改）
- **改动背景与原理**：
  - 针对用户反馈的"打不开"问题，溯源底层发现缺少 macOS 原生代码签名与隔离属性，导致 Gatekeeper 静默拦截；
  - 同时由于应用为 `LSUIElement=true` 常驻型应用，启动时缺少可视化反馈。
  - 完成 `DeviceDetector` 的 Swift 6 并发适配，并为打包好的应用执行 Ad-hoc 签名与隔离清除。
- **主要改动细节**：
  1. 引入 `codesign --force --deep --sign -` 完整签名，消除 AMFI/Gatekeeper 运行拦截，`codesign -vvv` 验证满足系统 Designated Requirement。
  2. 在 `AppDelegate` 中加入启动 0.3s 自动展开控制台机制，使用户双击即感知 App 已拉起。
  3. 完成 `DeviceDetector` 与 `MediaScanner` 在主应用的装配联调。
- **验证结果**：`open /Users/qianliangjun/Desktop/DJIToDrive.app` 运行正常，后台进程活跃（PID 17019），桌面双击即刻打开并展开控制台。
---
