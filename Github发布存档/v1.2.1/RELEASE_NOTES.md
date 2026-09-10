# 🛸 DJIToGoogleDrive v1.2.1 官方更新版 (Official Release)

> 📌 **发布日期**：2026-09-10  
> 🏷️ **版本号**：`v1.2.1`  
> 💻 **支持系统**：macOS 13.0 (Ventura) 及更高版本（原生支持 Apple Silicon M系列 与 Intel 芯片）

---

### ✨ 核心特性与重大升级 (Highlights)

1. **🛡️ Google Drive 官方 502/5xx 指数退避与状态探针自愈**：
   - 彻底解决大文件（10GB~20GB+ 4K/8K 视频）长时间上传因代理长连接断开或 Google 边缘服务器抖动导致的 `502 Bad Gateway` 报错；
   - 自动启动 2s+ 指数退避休眠，并向 Google 发送 `bytes */total` 空探针校验云端接收边界，支持 5 次后台静默自愈续传；
   - 彻底净化错误提示，拦截原始 HTML 乱码输出，界面始终整洁美观。
2. **🏷️ 大疆官方学名标准对齐**：
   - 废除“DJI 360 全景相机”等通俗描述，全面对齐大疆官方标准学名：**`DJI Osmo 360`**、**`DJI Osmo Pocket 3`**、**`DJI Osmo Pocket 4`**、**`DJI Osmo Action 4/5 Pro`**。
3. **🔍 芯片级出厂序列号 (SN) 硬件感知**：
   - 调用 macOS 原生 IOKit 底层总线，直接从相机硬件固件解析提取设备出厂号（如 **`SN: BBBF1E26`**）；
   - 设备卡片与素材列表中清晰展现专属序列号徽章，方便多相机多机位素材溯源管理。
4. **🔔 后台静默常驻与即插即感自动提醒**：
   - App 原生基于 `LSUIElement` 24小时静默常驻在屏幕右上角菜单栏（占用仅约 30MB 内存，0% CPU）；
   - **一插上相机**：屏幕右上角 0.1 秒内响起提示音并弹出 macOS 原生系统横幅：
     `🔌 已识别 DJI Osmo 360 [SN: BBBF1E26]`，并自动平滑展开控制台，一步直达同步按钮！
5. **🚀 App 内部一键自动升级与无感自更重启**：
   - 告别繁琐的“跳转网页 ➔ 手动下载 zip ➔ 手动解压覆盖”；
   - 在偏好设置「软件更新」卡片中点击 **「🚀 一键自动更新并重启」**，App 内部流式下载并实时显示百分比，下载完成后后台自动无缝替换 `/Applications` 并自动重启拉起新版！

---

### 📦 安装与升级方式 (Installation)

1. **已安装用户（老用户）**：
   - 打开 App 偏好设置 ➔ 「软件更新与版本」 ➔ 直接点击 **「🚀 一键自动更新并重启」** 即可无感升级！
2. **全新安装用户**：
   - 下载下方的 **`DJIToGoogleDrive-v1.2.1-macOS.zip`**；
   - 解压后将 **`DJIToGoogleDrive.app`** 拖入「应用程序」文件夹（/Applications）即可双击打开使用。

---

### 🔐 安全校验和 (SHA-256 Checksums)

```text
5880df08aac6c1f5b938755defad0bd7773f2c24a04347a38873fd2ac29d2a48  DJIToGoogleDrive-v1.2.1-macOS.zip
9dcb95abaa93e4d294ed8d0f6fc3adfc57b2ad302e12b721575496b153295010  DJIToGoogleDrive-v1.2.1-Source.zip
```
