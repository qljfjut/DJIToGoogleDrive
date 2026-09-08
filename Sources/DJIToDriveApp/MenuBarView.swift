// ====================================
// 📁 文件职责：菜单栏常驻快捷控制台 SwiftUI 视图
// 包含：设备连接指示卡片、待处理媒体摘要、快速同步触发器、设置面板跳转与退出操作
// 不包含：底层的卷盘物理监听与 Google Drive 网络传输
// 依赖：SwiftUI, AppKit
// ====================================

import SwiftUI

struct MenuBarView: View {
    @State private var isConnected: Bool = false
    @State private var deviceName: String = "未检测到 DJI 设备"
    @State private var deviceDetail: String = "请插入 Pocket 3 / 4、360 全景相机或插卡"
    @State private var pendingFileCount: Int = 0
    @State private var totalSizeBytes: Int64 = 0
    @State private var isSyncing: Bool = false
    @State private var syncProgress: Double = 0.0

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
        .frame(width: 350, height: 400)
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
                .fill(isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(isConnected ? "已就绪" : "待机中")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var deviceStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isConnected ? "sdcard.fill" : "cable.connector.slash")
                    .foregroundColor(isConnected ? .blue : .gray)
                    .font(.title2)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(deviceDetail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var syncSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("待同步素材")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(pendingFileCount) 个文件 · \(formattedBytes(totalSizeBytes))")
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
            .disabled(!isConnected || isSyncing)

            Button(action: scanDeviceManually) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("手动重新扫描挂载设备")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isSyncing)
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

    private func startSyncAction() {
        isSyncing = true
        syncProgress = 0.05
    }

    private func scanDeviceManually() {
        // 稍后在 P2 接入 DeviceDetector 触发
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
