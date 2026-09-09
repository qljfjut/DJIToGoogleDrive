# 🛸 DJIToGoogleDrive v1.0.0 创世版本 (Initial Release)

> 📌 **发布日期**：2026-09-08  
> 🏷️ **版本号**：`v1.0.0`

### 🌱 创世功能特性
1. **macOS 原生菜单栏宿主**：基于 SwiftUI + AppKit 开发，不占 Dock 栏，纯静默常驻。
2. **底层硬件挂载感知**：基于 POSIX `/Volumes` 事件监听，毫秒级感知 DJI 设备插入与拔出。
3. **双存储感知**：同时感知机身内部存储与外置 TF/SD 卡并呈现双卡片视图。
4. **Google Drive 16MB Chunk 断点续传**：基于 Resumable Upload 协议，支持大文件切片与重试。
5. **极速指纹账本**：首尾 4MB SHA-256 采样，极速对账排重。
6. **macOS Keychain 硬件安全加密**：敏感 Client Secret 与 Token 零明文存储。
