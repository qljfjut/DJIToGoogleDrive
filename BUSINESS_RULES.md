# 📖 DJIToDrive 核心业务与设备规约 (Business Rules Specification)

> 📌 **版本**：`v1.0.0` | 📅 **最后更新**：`2026-09-08` | 🏷️ **核心适用设备**：`DJI 360 全景相机`、`Osmo Pocket 3`、`Osmo Pocket 4`

---

## 一、 支持设备矩阵与挂载识别规约 (Supported Devices & Mount Patterns)

系统通过 `NSWorkspace.didMountNotification` 监听物理卷盘插入。当卷盘满足以下任一条件时，判定为有效设备：

### 1. 设备特征映射表

| 设备型号 | 卷标典型特征 (Volume Name) | 典型目录层级 | 特殊伴生文件与处理规则 |
| :--- | :--- | :--- | :--- |
| **DJI Osmo Pocket 3** | `OSMO_POCKET` / `NO NAME` / 卷内含 `DJI_` 前缀文件 | `/Volumes/<NAME>/DCIM/100MEDIA/` | 1. 伴生 `.LRF`（低码率预览）**强制过滤**<br>2. 关联的 DJI Mic 2 `.WAV`（32-bit float 音频）**必须完整保留同步**<br>3. 伴生 `.SRT`（曝光与色彩元数据）**保留同步** |
| **DJI Osmo Pocket 4** | 继承 Pocket 系列特征，预留 8K/高码率命名空间 | `/Volumes/<NAME>/DCIM/*MEDIA/` | 兼容未来 Pocket 4 拓展目录结构 |
| **DJI 360 全景相机** | `DJI_360` / `PANORAMA` / 卷内含全景双鱼眼流 | `/Volumes/<NAME>/DCIM/PANORAMA/` 或 `*MEDIA/` | 1. 360 双目未缝合流/缝合后大码率视频（.MP4 / .MOV）**高优先级同步**<br>2. 伴生低清预览与缩略图（.LRF / .THM）**自动过滤** |

### 2. 挂载方式双轨支持
- **模式 A（高速读卡器插 TF/SD 卡）**：格式通常为 `exFAT` 或 `FAT32`，挂载点形如 `/Volumes/NO NAME` 或 `/Volumes/Untitled`。系统扫描其根目录下是否存在 `DCIM` 且其子目录含 `DJI_*.MP4` 或类似签名。
- **模式 B（Type-C 数据线直连设备）**：设备开启 USB 大容量存储模式（Mass Storage），挂载为常规 UMS 盘符，识别机制与读卡器一致。

---

## 二、 媒体文件白名单与智能过滤规约 (Filter Rules)

### 1. 采纳同步白名单 (Sync Whitelist)
以下扩展名（忽略大小写）一律加入上传就绪队列：
- **主视频流**：`.mp4`, `.mov`
- **高动态范围/RAW 照片**：`.dng`, `.jpg`, `.jpeg`
- **专业伴声音频轨（DJI Mic 2 备份）**：`.wav`
- **飞控与曝光字幕元数据**：`.srt`

### 2. 丢弃/忽略黑名单 (Sync Blacklist)
为避免极度浪费 Google Drive 宝贵存储与带宽，以下文件**默认硬性忽略**：
- **低清代理视频**：`.lrf`（Low Resolution Files，用于手机 Mimo App 快速剪辑预览）
- **缩略图文件**：`.thm`（Thumbnail Files）
- **macOS 系统元数据与垃圾**：`._*`（AppleDouble 文件）、`.DS_Store`、`.Trashes/`、`.Spotlight-V100/`

---

## 三、 Google Drive 云端归档拓扑规约 (Cloud Directory Hierarchy)

为了让创作者云端素材井井有条，所有文件统一按照 **拍摄日期（或创建时间）** 动态创建云端目录结构：

```
Google Drive 根目录
└── 📁 DJI_Media/
    ├── 📁 2026-09-08/
    │   ├── 🎬 DJI_0001.MP4
    │   ├── 📄 DJI_0001.SRT
    │   ├── 🎵 DJI_0001_MIC2.WAV
    │   └── 📷 DJI_0002.DNG
    └── 📁 2026-09-09/
        ├── 🎬 DJI_0003.MP4
        └── ...
```

### 归档命名与时间戳提取算法：
1. **优先度 1**：读取文件 EXIF / QuickTime 视频元数据中的 `CreationDate`。
2. **优先度 2**：若元数据不可读，则解析文件系统修改时间 `fileModificationDate`。
3. **格式化模板**：`YYYY-MM-DD`（如 `2026-09-08`）。

---

## 四、 本地去重账本机制 (Zero-Duplicate Hash Ledger)

### 1. 唯一指纹生成算法 (Fingerprint)
为避免重复上传造成的时间与流量浪费，本地维护去重账本：
- **基础指纹**：`SHA-256(前 4MB + 末 4MB + 真实文件字节大小)`。
  - *原理*：航拍大视频动辄 10GB+，全量读取 SHA-256 极其耗时；对首尾各 4MB 及总字节数进行组合哈希，耗时只需数毫秒且碰撞概率趋近于 0。
- **辅助校验**：`文件名` + `最后修改时间戳 (mtime)`。

### 2. 账本存储与状态流转
- **账本路径**：`~/Library/Application Support/DJIToDrive/ledger.json`
- **记录字段**：
  ```json
  {
    "fingerprint": "a3f8c...90b",
    "source_file_name": "DJI_0042.MP4",
    "file_size": 4294967296,
    "cloud_file_id": "1A2B3C4D5E6F",
    "cloud_path": "DJI_Media/2026-09-08/DJI_0042.MP4",
    "status": "COMPLETED",
    "uploaded_at": "2026-09-08T22:15:00Z"
  }
  ```
- 若扫描到某文件指纹已存在且状态为 `COMPLETED`，控制台自动标记为 `[已同步]`，默认不勾选。

---

## 五、 分片续传核心常量配置 (Transfer Constants)

```swift
public enum BusinessConstants {
    /// Google Drive Resumable Upload 要求必须为 256 KB (262,144 bytes) 的倍数
    /// 16MB = 16 * 1024 * 1024 = 16,777,216 bytes (恰为 256KB 的 64 倍)
    public static let CHUNK_SIZE_BYTES: Int = 16 * 1024 * 1024
    
    /// 默认云端根目录名称
    public static let DEFAULT_CLOUD_ROOT_FOLDER: String = "DJI_Media"
    
    /// 本地 OAuth 监听端口
    public static let OAUTH_REDIRECT_PORT: UInt16 = 8085
    
    /// 网络断线重试退避基数（秒）
    public static let RETRY_BASE_DELAY_SECONDS: Double = 2.0
}
```
