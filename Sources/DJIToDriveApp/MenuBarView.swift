// ====================================
// 📁 文件职责：菜单栏快捷控制面板 SwiftUI 视图与设备感知/上传引擎状态绑定
// 包含：硬件热插拔实时响应、媒体资产扫描与过滤汇总、Google Drive 分片上传触发与进度反馈
// 不包含：底层的 POSIX 监听与 Keychain 底层 API
// 依赖：SwiftUI, AppKit, DeviceDetector, MediaScanner, AuthManager, UploadEngine
// ====================================

import SwiftUI
import DeviceDetector
import MediaScanner
import AuthManager
import UploadEngine

struct MenuBarView: View {
    @StateObject private var detector = DeviceDetector()
    @ObservedObject private var authManager = AuthManager.shared
    @StateObject private var uploadEngine = UploadEngine()
    private let scanner = MediaScanner()
    
    @State private var scanResult: ScanResult = .empty
    @State private var isScanning: Bool = false
    @State private var uploadErrorMessage: String?
    @State private var uploadSuccessMessage: String?
    
    // 独立设置窗口引用
    @State private var settingsWindow: NSWindow?
    @State private var lastAutoSyncedDeviceId: String?

    private var hasActiveDevice: Bool {
        detector.activeDevice != nil
    }

    var body: some View {
        VStack(spacing: 14) {
            headerSection
            Divider()
            deviceStatusSection
            Divider()
            syncSummarySection
            Spacer(minLength: 8)
            actionButtonGroup
            Divider()
            footerSection
        }
        .padding(14)
        .frame(width: 360, height: 430)
        .task(id: detector.activeDevice?.id) {
            await triggerMediaScan()
            if let dev = detector.activeDevice,
               dev.id != lastAutoSyncedDeviceId,
               authManager.isAuthenticated,
               !uploadEngine.isUploading,
               !scanResult.items.isEmpty {
                lastAutoSyncedDeviceId = dev.id
                handleSyncOrAuthAction(isAuto: true)
            }
        }
    }

    // MARK: - 子视图拆分 (Subviews)

    private var headerSection: some View {
        HStack(spacing: 10) {
            if let logoImage = loadAppIcon() {
                Image(nsImage: logoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .cornerRadius(6)
            } else {
                Image(systemName: "video.badge.waveform.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("DJIToDrive")
                    .font(.headline)
                    .fontWeight(.bold)
                Text(authManager.isAuthenticated ? "Google Drive 已就绪" : "Google 账号未连接")
                    .font(.caption2)
                    .foregroundColor(authManager.isAuthenticated ? .secondary : .orange)
            }
            Spacer()
            Circle()
                .fill(hasActiveDevice ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(hasActiveDevice ? "设备就绪" : "等待连接")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private func loadAppIcon() -> NSImage? {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        return NSImage(named: NSImage.applicationIconName)
    }

    private var deviceStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: hasActiveDevice ? "sdcard.fill" : "cable.connector.slash")
                    .foregroundColor(hasActiveDevice ? .blue : .gray)
                    .font(.title2)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(detector.activeDevice?.displayName ?? "未检测到 DJI 设备")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(detector.activeDevice?.volumeURL.path ?? "请插入 Pocket 3 / 4、360 全景相机或插卡")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isScanning {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if detector.connectedDevices.count > 1 {
                    Menu {
                        ForEach(detector.connectedDevices) { dev in
                            Button {
                                detector.selectDevice(dev)
                            } label: {
                                if dev.id == detector.activeDevice?.id {
                                    Label(dev.displayName, systemImage: "checkmark")
                                } else {
                                    Text(dev.displayName)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var syncSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("待同步高价值素材")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(scanResult.items.count) 个文件 · \(formattedBytes(scanResult.totalSizeBytes))")
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            if uploadEngine.isUploading, let progress = uploadEngine.currentProgress {
                VStack(spacing: 4) {
                    ProgressView(value: progress.overallProgress, total: 1.0)
                        .progressViewStyle(.linear)
                    HStack {
                        Text("[\(progress.currentFileIndex)/\(progress.totalFiles)] \(progress.currentFilename)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(progress.overallProgress * 100))%")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if let success = uploadSuccessMessage {
                        Text(success)
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else if let err = uploadErrorMessage {
                        Text(err)
                            .font(.caption2)
                            .foregroundColor(.red)
                    } else if scanResult.ignoredCount > 0 {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                                .font(.caption2)
                            Text("已自动过滤 \(scanResult.ignoredCount) 个 .LRF 低清代理 (节省 \(formattedBytes(scanResult.ignoredSizeBytes)))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack {
                            Label("自动过滤 .LRF 预览代理", systemImage: "checkmark.shield")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Label("保留 .WAV/.SRT", systemImage: "waveform")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
    }

    private var actionButtonGroup: some View {
        VStack(spacing: 8) {
            Button(action: { handleSyncOrAuthAction(isAuto: false) }) {
                HStack {
                    Image(systemName: uploadEngine.isUploading ? "arrow.triangle.2.circlepath" : (authManager.isAuthenticated ? "icloud.and.arrow.up.fill" : "key.fill"))
                    Text(syncButtonTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasActiveDevice || scanResult.items.isEmpty || uploadEngine.isUploading)

            Button(action: scanDeviceManually) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text(isScanning ? "正在扫描设备..." : "手动重新扫描挂载设备")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isScanning || uploadEngine.isUploading)
        }
    }

    private var syncButtonTitle: String {
        if uploadEngine.isUploading {
            return "正在 16MB Chunk 断点续传中..."
        }
        if !authManager.isAuthenticated {
            return "请先在设置中连接 Google 账号"
        }
        return "一键开始上传至 Google Drive"
    }

    private var footerSection: some View {
        HStack {
            Button("偏好设置与 Google 账号...") {
                openPreferences()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)

            Spacer()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - 业务交互动作 (Actions)

    private func triggerMediaScan() async {
        guard let device = detector.activeDevice else {
            scanResult = .empty
            return
        }
        isScanning = true
        let result = await scanner.scan(dcimURL: device.dcimURL)
        await MainActor.run {
            self.scanResult = result
            self.isScanning = false
        }
    }

    private func handleSyncOrAuthAction(isAuto: Bool = false) {
        if !authManager.isAuthenticated {
            if !isAuto {
                openPreferences()
            }
            return
        }
        
        guard !scanResult.items.isEmpty, !uploadEngine.isUploading else { return }
        
        uploadErrorMessage = nil
        uploadSuccessMessage = nil
        
        let itemCount = scanResult.items.count
        let totalSizeStr = formattedBytes(scanResult.totalSizeBytes)
        let deviceName = detector.activeDevice?.displayName ?? "DJI 设备"
        
        Task {
            do {
                try await uploadEngine.uploadItems(scanResult.items)
                await MainActor.run {
                    self.uploadSuccessMessage = "🎉 全量素材已成功同步到 Google Drive (DJI_Media 目录)！"
                    AppDelegate.sendNotification(
                        title: "DJIToDrive 素材同步完成",
                        body: "来自 \(deviceName) 的 \(itemCount) 个素材 (\(totalSizeStr)) 已成功同步至 Google Drive！"
                    )
                }
            } catch {
                await MainActor.run {
                    self.uploadErrorMessage = "上传失败: \(error.localizedDescription)"
                    AppDelegate.sendNotification(
                        title: "DJIToDrive 同步未完成",
                        body: "同步遇到问题: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func scanDeviceManually() {
        detector.scanExistingVolumes()
        Task {
            await triggerMediaScan()
        }
    }

    private func openPreferences() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "DJIToDrive 偏好设置"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
