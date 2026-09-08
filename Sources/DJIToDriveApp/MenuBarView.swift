// ====================================
// 📁 文件职责：菜单栏快捷控制面板 SwiftUI 视图与设备感知状态绑定
// 包含：硬件热插拔实时响应、媒体资产扫描与过滤汇总、手动扫描重试
// 不包含：底层 Google Drive HTTP 协议与 Keychain 读写
// 依赖：SwiftUI, AppKit, DeviceDetector, MediaScanner
// ====================================

import SwiftUI
import DeviceDetector
import MediaScanner

struct MenuBarView: View {
    @StateObject private var detector = DeviceDetector()
    private let scanner = MediaScanner()
    
    @State private var scanResult: ScanResult = .empty
    @State private var isScanning: Bool = false
    @State private var isSyncing: Bool = false
    @State private var syncProgress: Double = 0.0

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
        .frame(width: 360, height: 420)
        .task(id: detector.activeDevice?.id) {
            await triggerMediaScan()
        }
    }

    // MARK: - 子视图拆分 (Subviews)

    private var headerSection: some View {
        HStack {
            Image(systemName: "video.badge.waveform.fill")
                .foregroundColor(.accentColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("DJIToDrive")
                    .font(.headline)
                    .fontWeight(.bold)
                Text("DJI 媒体全自动云端同步器")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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

    private var deviceStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: hasActiveDevice ? "sdcard.fill" : "cable.connector.slash")
                    .foregroundColor(hasActiveDevice ? .blue : .gray)
                    .font(.title2)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(detector.activeDevice?.deviceType.rawValue ?? "未检测到 DJI 设备")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(detector.activeDevice?.volumeName ?? "请插入 Pocket 3 / 4、360 全景相机或插卡")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isScanning {
                    ProgressView()
                        .scaleEffect(0.7)
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

            if isSyncing {
                VStack(spacing: 4) {
                    ProgressView(value: syncProgress, total: 1.0)
                        .progressViewStyle(.linear)
                    HStack {
                        Text("正在分片同步到 Google Drive...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(syncProgress * 100))%")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if scanResult.ignoredCount > 0 {
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
            Button(action: startSyncAction) {
                HStack {
                    Image(systemName: isSyncing ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.up.fill")
                    Text(isSyncing ? "正在同步中..." : "一键开始上传至 Google Drive")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasActiveDevice || scanResult.items.isEmpty || isSyncing)

            Button(action: scanDeviceManually) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text(isScanning ? "正在扫描设备..." : "手动重新扫描挂载设备")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isScanning || isSyncing)
        }
    }

    private var footerSection: some View {
        HStack {
            Button("偏好设置...") {
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

    private func startSyncAction() {
        isSyncing = true
        syncProgress = 0.05
    }

    private func scanDeviceManually() {
        detector.scanExistingVolumes()
        Task {
            await triggerMediaScan()
        }
    }

    private func openPreferences() {
        // 稍后在 P3 接入独立 Settings 窗口
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
