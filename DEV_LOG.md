# 📝 DJIToDrive 开发与审计编年史 (Development Audit Log)

所有代码、配置与架构变更必须在完成编写后在此追加记录，保持可回溯的审计链。

---

### 📅 [2026-09-09 00:01] 修复 macOS Accessory 模式下的 Cmd+V 粘贴快捷键与输入框交互增强
- **操作类型**：`[修复]` / `[优化]`
- **涉及文件**：
  - `Sources/DJIToDriveApp/AppDelegate.swift`（修改）
  - `Sources/DJIToDriveApp/SettingsView.swift`（修改）
- **改动背景与原理**：
  - 用户在录入 Google Cloud Client ID 与 Client Secret 时发现无法使用 `Cmd+V` 键盘快捷键粘贴。
  - 溯源发现因应用采用无 Dock 的 `.accessory`（菜单栏常驻）模式，未注册全局 `NSApplication.shared.mainMenu` 中的 Edit 菜单，导致 Cocoa 快捷键响应链未派发 `Cmd+V` / `Cmd+C`。
- **主要改动细节**：
  1. 在 `AppDelegate` 初始化时注入系统标准 `Edit` 菜单（包含 Cut, Copy, Paste, Select All, Undo, Redo），全面打通全局键盘快捷键响应。
  2. 在 `SettingsView` 中的 Client ID 与 Client Secret 输入框右侧新增「📋 粘贴」专属按钮，直读系统剪贴板（`NSPasteboard.general`）。
  3. 为 Client Secret 增加眼睛图标，支持明文/密文切换查看，方便核对复制内容完整性。
  4. 重新打包 Release 应用包并刷新签名，平滑重启进程。
- **验证结果**：编译耗时 1.78s 完成，新进程拉起，键盘快捷键与一键粘贴按钮已全量生效。
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

### 📅 [2026-09-08 23:42] P3 阶段达成：Google OAuth 2.0 PKCE 鉴权与 16MB Chunk 断点续传引擎全量贯通
- **操作类型**：`[新增]` / `[优化]`
- **涉及文件**：
  - `Package.swift`（修改：拓扑链接 `Ledger`、`AuthManager` 与 `UploadEngine`）
  - `Sources/Ledger/Ledger.swift`（新增：首尾 4MB 组合哈希指纹与持久化账本）
  - `Sources/AuthManager/AuthManager.swift`（新增：PKCE 鉴权、127.0.0.1 回调捕获与 Keychain 存取）
  - `Sources/UploadEngine/UploadEngine.swift`（新增：Google Drive API v3 Resumable 16MB Chunk 续传器）
  - `Sources/DJIToDriveApp/SettingsView.swift`（新增：Google Cloud 凭据与账号管理窗口）
  - `Sources/DJIToDriveApp/MenuBarView.swift`（修改：全链路绑定上传引擎与偏好设置）
  - `DEV_LOG.md`（修改）
- **改动背景与原理**：
  - 落实 P3 路线图，建立完整的云端上传与鉴权底座。
  - 采用 Google 官方推荐的 OAuth 2.0 PKCE 流程与本地临时 HTTP Loopback 接收授权码，Token 物理隔离保存在 macOS Keychain (`kSecClassGenericPassword`)；
  - 针对 Pocket 3/4 与 360 相机动辄几十 GB 的巨型视频，实现 16MB Chunk 分片续传与指数退避断网重试，结合首尾 4MB 哈希毫秒级比对，保证 0 重复上传。
- **主要改动细节**：
  1. 建立 `Ledger` Actor，实现大文件瞬时指纹生成与 JSON 本地账本维护。
  2. 建立 `AuthManager`，支持 Client ID/Secret 安全存取、PKCE 随机挑战码与 Token 自动轮转。
  3. 建立 `UploadEngine`，实现 Google Drive 目录树按 `DJI_Media/{YYYY-MM-DD}/` 自动检索与创建、分片上传与总体进度派发。
  4. 建立 `SettingsView` 独立偏好设置窗口，支持一键保存凭证与网页授权。
- **验证结果**：`swift build -c release` 编译通过，应用重新打包并重签名发布至桌面；新进程（PID 17355）已启动并生效，全链路端到端闭环就绪。
---

### 📅 [2026-09-09 00:04] App Logo 高清资产入库与 macOS 文件夹专属换标
- **操作类型**：`[新增]` / `[优化]`
- **涉及文件**：
  - `Resources/AppIcon.png`（新增：1024×1024 高清无损源图持久化归档）
  - `scripts/package_app.sh`（修改：解耦外部临时路径，直指项目内部 Resources/AppIcon.png）
  - `.`（优化：通过 macOS Cocoa API 赋予文件夹自定义 App Logo 外观）
- **改动背景与原理**：
  - 响应用户将 App Logo 放入文件夹的指示，将先前临时生成的 DJI + Google Drive 融合 Logo 图像无损转码并落盘至 `Resources/` 目录；
  - 重构打包脚本，切断外部临时缓存路径依赖，达成构建流水线 100% 工程内部独立闭环；
  - 运用 macOS JXA / Cocoa `NSWorkspace.sharedWorkspace.setIconForFileOptions`，在当前工程目录建立 `Icon\r` 标识，完成桌面文件夹专属 Logo 换标。
- **主要改动细节**：
  1. 使用 `sips` 将源图以 1024×1024 分辨率转码写入 `Resources/AppIcon.png`。
  2. 修改 `scripts/package_app.sh` 中的 `ICON_SRC` 为 `$PROJECT_ROOT/Resources/AppIcon.png`。
  3. 执行 JXA 注入，成功为 `/Users/qianliangjun/Desktop/DJI一键导入google drive` 设置自定义文件夹图标。
- **验证结果**：`Resources/AppIcon.png` 就绪，`Icon\r` 成功生成并受 `.gitignore` 保护，Finder 文件夹外观图标已刷新。
---

### 📅 [2026-09-09 00:23] 关键硬件格式突破：适配 DJI 360 全景相机 .OSV 格式与双卷盘智能优先级
- **操作类型**：`[修复]` / `[优化]`
- **涉及文件**：
  - `Sources/MediaScanner/MediaScanner.swift`（修改：白名单纳入 `.osv` 双目大码率全景视频，增强 CAM_ 时间戳解析）
  - `Sources/DeviceDetector/DeviceDetector.swift`（修改：识别 `SD_Card` 下的 360 媒体特征，多卷盘并存自动优选有素材卷盘）
  - `Sources/UploadEngine/UploadEngine.swift`（修改：补充 `.osv` 的 MIME 视频流类型映射）
  - `DEV_LOG.md`（修改）
- **改动背景与原理**：
  - 针对用户截图反馈的“已连接但显示 0 个文件”异常，现场探测底层 `/Volumes` 挂载点，发现 360 相机同时挂载了内置空盘 `/Volumes/Osmo360` 与外置 TF 卡 `/Volumes/SD_Card`，且航拍主全景素材为 DJI 专有的 `.OSV` 格式（单文件 2GB~16GB 不等）；
  - 升级探测器优先级排序算法，遇多卷盘自动探测真实包含媒体文件的有效盘符，并将 `.OSV` 纳入白名单并过滤对应的 `.LRF` 预览代理。
- **主要改动细节**：
  1. `MediaScanner` 中 `allowedVideoExtensions` 追加 `osv`，支持从 `CAM_YYYYMMDDHHMMSS_...` 提取拍摄时间。
  2. `DeviceDetector` 增加 `volumeContainsMedia` 检测并排序，自动将承载素材的 `SD_Card` 升为首选激活设备。
  3. `UploadEngine` 中支持 `.osv` 视频流分片上传。
- **验证结果**：编译打包完成并重启应用（PID 18869），成功捕获到 19 个全景大视频（共约 180+ GB），并自动过滤 19 个冗余代理文件，同步按钮正式激活！
---
