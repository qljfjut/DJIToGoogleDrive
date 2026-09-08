# 🏗️ DJIToDrive 系统架构设计书 (Architecture Specification)

> 📌 **版本**：`v1.0.0` | 📅 **最后更新**：`2026-09-08` | 🏷️ **平台**：`macOS 13.0+ (Ventura / Sonoma / Sequoia)`

---

## 一、 系统架构总览 (System Architecture Overview)

`DJIToDrive` 是一款专为摄影师与航拍创作者打造的 macOS 原生菜单栏常驻应用（MenuBar App）。其核心目标是实现 DJI 360 全景相机、Osmo Pocket 3 / 4 等设备插入 Mac 时，全自动智能识别素材并高保真、断点续传同步至 Google Drive。

```mermaid
graph TD
    subgraph 物理介质层
        Dev1[DJI Osmo Pocket 3 / 4] -->|Type-C 直连 / 读卡器| Vol[/Volumes/* 卷盘挂载/]
        Dev2[DJI 360 全景相机] -->|Type-C 直连 / 读卡器| Vol
    end

    subgraph 系统事件与感知层
        Vol -->|NSWorkspace.didMountNotification| Detector[DeviceDetector 设备识别器]
        Detector -->|有效设备特征匹配| Scanner[MediaScanner 媒体过滤扫描引擎]
    end

    subgraph 业务逻辑与过滤层
        Scanner -->|保留 .MP4/.MOV/.JPG/.DNG/.WAV/.SRT| FilteredFiles[待上传素材清单]
        Scanner -.->|过滤 .LRF/.THM/._*| Ignored[丢弃冗余代理]
        FilteredFiles --> Ledger{Ledger 去重哈希账本}
        Ledger -->|新素材待传| TaskQueue[UploadTaskQueue 队列管理器]
        Ledger -->|已上传过| Skip[跳过防重]
    end

    subgraph 交互表现层 (SwiftUI)
        Detector -->|触发半自动通知| MenuBar[MenuBar 状态栏组件]
        MenuBar --> Dashboard[ConsoleReviewPanel 审查与控制台]
        Dashboard -->|一键开始上传| TaskQueue
    end

    subgraph 核心传输与安全层
        TaskQueue --> Engine[URLSession Resumable Upload 断点续传器]
        Engine -->|分片上传 16MB/Chunk| GDriveAPI[Google Drive REST API v3]
        Auth[AuthManager OAuth 2.0 PKCE] -->|本地 127.0.0.1 回调| GDriveAPI
        Auth -->|Token 硬件加密存取| Keychain[(macOS Keychain)]
    end
```

---

## 二、 模块划分与代码地图 (Module Breakdown)

项目采用 **Swift Package Manager (SPM)** 进行模块化组织，杜绝巨石单文件。

| 模块名 | 核心职责 | 主要依赖 |
| :--- | :--- | :--- |
| **`AppCore`** | 应用生命周期、状态栏 NSStatusItem 托管、系统通知分发 | `AppKit`, `SwiftUI` |
| **`DeviceDetector`** | 监听卷盘挂载/卸载事件，匹配 Pocket 3/4 与 360 全景相机特征 | `Foundation`, `AppKit` |
| **`MediaScanner`** | 遍历 DCIM 结构，执行文件白黑名单过滤，提取拍摄时间与元数据 | `Foundation` |
| **`UploadEngine`** | 原生 `URLSession` 分片断点续传器（Resumable Chunk）、进度计算与断网指数退避重试 | `Foundation` |
| **`AuthManager`** | Google OAuth 2.0 PKCE 流程实现、本地 Loopback 回调监听、Token 自动刷新与 Keychain 托管 | `AuthenticationServices`, `Security` |
| **`Ledger`** | 本地去重账本（SQLite / JSON），维护 SHA-256、文件大小、修改时间与云端 File ID 映射 | `Foundation` |
| **`UIViews`** | SwiftUI 界面集：状态栏快捷弹窗、素材快速审查确认表单、配置与向导窗口 | `SwiftUI` |

---

## 三、 工程铁律与编码规范 (Engineering Mandates)

### 1. 📏 单文件行数强制上限
- **任何 Swift 源码文件物理行数严禁超过 800 行**。
- 一旦接近 600 行预警线，必须主动执行模块拆分（如拆分 Extension、ViewComponent 或专用 Controller）。

### 2. 📁 文件顶部 AI 可读标准注释
所有新创建或修改的 Swift 源码文件必须在首行注入以下结构化注释：
```swift
// ====================================
// 📁 文件职责：<一句话说明本文件管理的功能域>
// 包含：<列举本文件包含的主要类型/功能>
// 不包含：<明确排除的功能，防止职责蔓延>
// 依赖：<本文件依赖的其他模块或系统框架>
// ====================================
```

### 3. 🚫 严禁魔法数字 (No Magic Numbers)
所有核心业务数值必须显式具名定义在常量集中：
```swift
enum TransferConfig {
    /// 默认单次分片上传大小（Google Drive 建议为 256KB 的整数倍，这里取 16MB）
    static let defaultChunkSizeBytes: Int = 16 * 1024 * 1024
    /// 最大并发上传大文件数
    static let maxConcurrentUploads: Int = 2
    /// 网络中断最大重试次数
    static let maxRetryAttempts: Int = 5
}
```

### 4. 🛠️ 现代化官方构建工具链铁律
- 严禁手写脆弱的裸 `swiftc` 终端命令进行长链构建。
- 必须无条件使用官方 Swift Package Manager（SPM）构建命令：
  - 构建开发版：`swift build`
  - 构建正式版：`swift build -c release`
  - 执行单元测试：`swift test`

---

## 四、 关键技术选型与实现细节

### 1. 原生断点续传器 (Resumable Upload Engine)
针对 360 全景巨型视频（5.7K/8K 单文件 20GB+）与 4K 120fps 高码率视频：
- 调用 Google Drive API v3 的 `POST /upload/drive/v3/files?uploadType=resumable` 初始化上传会话，获取唯一 `Session-URI`。
- 按 16MB 步长（256KB 整数倍）切片，使用 `PUT` 请求发送 `Content-Range: bytes START-END/TOTAL`。
- 本地记录每个文件未完成的 `Session-URI` 与 `bytes_uploaded`，断网后自适应恢复续传，无需从头重传。

### 2. Google OAuth 2.0 PKCE 鉴权模型
- 零外部 SDK 依赖，纯原生实现。
- 生成高熵 `code_verifier` 并通过 SHA-256 衍生出 `code_challenge`。
- 启动临时本地 HTTP 服务（绑定 `127.0.0.1:8085`），在用户授权完成后捕获授权码 `code` 并换取 `access_token` 与 `refresh_token`。
- 所有凭证存储于 macOS 系统 Keychain (`kSecClassGenericPassword`)，严禁向本地文件写入明文。
