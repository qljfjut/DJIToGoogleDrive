// ====================================
// 📁 文件职责：菜单栏快捷控制面板 SwiftUI 视图与设备感知/上传引擎状态绑定
// 包含：双存储空间上下堆叠卡片展示、媒体素材多选/排除废片/全选工具栏、Google Drive 16MB Chunk 上传仪表盘与实时网速/ETA、严格手动触发同步
// 不包含：底层的 POSIX 硬件事件捕获与云端 HTTP 分片细节
// 依赖：SwiftUI, AppKit, DeviceDetector, MediaScanner, AuthManager, UploadEngine, Ledger
// ====================================

import SwiftUI
import DeviceDetector
import MediaScanner
import AuthManager
import UploadEngine
import Ledger

struct MenuBarView: View {
    @StateObject private var detector = DeviceDetector()
    @ObservedObject private var authManager = AuthManager.shared
    @StateObject private var uploadEngine = UploadEngine()
    private let scanner = MediaScanner()
    private let ledger = Ledger()
    
    // 双卷盘各自的扫描结果字典 (DeviceID -> ScanResult)
    @State private var volumeScanResults: [String: ScanResult] = [:]
    @State private var isScanning: Bool = false
    
    // 用户勾选的媒体素材路径集合 (fileURL.path) 与已入账本集合
    @State private var selectedItemIds: Set<String> = []
    @State private var uploadedItemIds: Set<String> = []
    
    @State private var uploadErrorMessage: String?
    @State private var uploadSuccessMessage: String?
    @State private var settingsWindow: NSWindow?
    @StateObject private var deletionHelper = MediaDeletionHelper()

    // MARK: - 聚合计算属性

    private var hasActiveDevice: Bool { !detector.connectedDevices.isEmpty }

    /// 多阶梯沉底排序：正在传输 ➔ 排队中 ➔ 已暂停 ➔ 待同步 ➔ ✅ 已同步沉底 ➔ 损坏0B/废片沉底
    private var allScannedItems: [ScannedMediaItem] {
        let raw = detector.connectedDevices.flatMap { volumeScanResults[$0.id]?.items ?? [] }
        return raw.sorted { a, b in
            let rankA = itemSortRank(a)
            let rankB = itemSortRank(b)
            if rankA != rankB {
                return rankA < rankB
            }
            if rankA == 1 {
                let idxA = uploadEngine.queuedItemIds.firstIndex(of: a.id) ?? Int.max
                let idxB = uploadEngine.queuedItemIds.firstIndex(of: b.id) ?? Int.max
                return idxA < idxB
            }
            return a.creationDate > b.creationDate
        }
    }

    private func itemSortRank(_ item: ScannedMediaItem) -> Int {
        if item.id == uploadEngine.currentUploadingItemId {
            return 0 // 🚀 传输中
        }
        if uploadEngine.queuedItemIds.contains(item.id) {
            return 1 // ⏳ 排队中
        }
        if uploadEngine.pausedItemIds.contains(item.id) {
            return 2 // ⏸️ 已暂停
        }
        let isUploaded = uploadedItemIds.contains(item.id) || uploadEngine.completedItemIds.contains(item.id)
        if !isUploaded && !item.isJunk && !item.isCorrupt {
            return 3 // 待同步
        }
        if isUploaded {
            return 4 // ✅ 已同步 (列表下方)
        }
        return 5 // 损坏0B / 废片 (列表最底)
    }

    private var allUploadedItems: [ScannedMediaItem] {
        allScannedItems.filter { uploadedItemIds.contains($0.id) || uploadEngine.completedItemIds.contains($0.id) }
    }

    private var selectedDeletableItems: [ScannedMediaItem] {
        selectedItems.filter {
            uploadedItemIds.contains($0.id) || uploadEngine.completedItemIds.contains($0.id) || $0.isJunk || $0.isCorrupt
        }
    }

    private var selectedItems: [ScannedMediaItem] {
        allScannedItems.filter { selectedItemIds.contains($0.id) }
    }

    private var selectedTotalBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(spacing: 8) {
            headerSection
            Divider()
            dualStorageSection
            Divider()
            mediaSelectionToolbar
            mediaChecklistSection
            Divider()
            metricsDashboardSection
            Spacer(minLength: 2)
            actionButtonGroup
            Divider()
            footerSection
        }
        .padding(.top, 20)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(width: 440, height: 645)
        .task { await scanAllConnectedVolumes() }
        .onChange(of: detector.connectedDevices) { _ in
            Task { await scanAllConnectedVolumes() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .djiSingleFileCompleted)) { notification in
            if let itemId = notification.userInfo?["itemId"] as? String {
                self.uploadedItemIds.insert(itemId)
                self.selectedItemIds.remove(itemId)
            }
        }
        .alert("确认彻底删除素材？", isPresented: $deletionHelper.showSingleDeleteConfirm, presenting: deletionHelper.itemToDelete) { item in
            Button("彻底删除", role: .destructive) {
                deletionHelper.executeSingleDelete(item: item) { freedBytes in
                    handleItemsDeleted(itemIds: [item.id], freedBytes: freedBytes)
                }
            }
            Button("取消", role: .cancel) {}
        } message: { item in
            Text("文件：\(item.filename)\n大小：\(formattedBytes(item.sizeBytes))\n\n该操作将直接从相机 SD 卡/存储中彻底删除该文件以释放空间，此操作不可撤销！")
        }
        .alert("确认批量清理素材？", isPresented: $deletionHelper.showBatchDeleteConfirm) {
            Button("彻底清理 (\(deletionHelper.itemsToBatchDelete.count) 个文件)", role: .destructive) {
                let itemsToDelete = deletionHelper.itemsToBatchDelete
                let ids = Set(itemsToDelete.map(\.id))
                deletionHelper.executeBatchDelete(items: itemsToDelete) { deletedCount, freedBytes in
                    handleItemsDeleted(itemIds: ids, freedBytes: freedBytes)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            let totalSize = deletionHelper.itemsToBatchDelete.reduce(0) { $0 + $1.sizeBytes }
            Text("即将从相机 SD 卡中彻底删除 \(deletionHelper.itemsToBatchDelete.count) 个文件，预计释放 \(formattedBytes(totalSize)) 空间！\n\n此操作不可撤销，请确认所选文件均已安全备份至 Google Drive。")
        }
    }

    // MARK: - 1. 顶部状态栏

    private var headerSection: some View {
        HStack(spacing: 10) {
            if let logoImage = loadAppIcon() {
                Image(nsImage: logoImage)
                    .resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28).cornerRadius(6)
            } else {
                Image(systemName: "video.badge.waveform.fill")
                    .foregroundColor(.accentColor).font(.title3)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("DJIToDrive").font(.headline).fontWeight(.bold)
                    Text("v1.2").font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15)).cornerRadius(3)
                }
                Text(authManager.isAuthenticated ? "Google Drive 已连接" : "Google 账号未连接")
                    .font(.caption2).foregroundColor(authManager.isAuthenticated ? .secondary : .orange)
            }
            Spacer()
            Circle().fill(hasActiveDevice ? Color.green : Color.orange).frame(width: 8, height: 8)
            Text(hasActiveDevice ? "\(detector.connectedDevices.count) 个存储就绪" : "等待连接")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - 2. 双存储空间上下堆叠卡片 (Dual Storage Stacked Display)

    private var dualStorageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if detector.connectedDevices.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "cable.connector.slash")
                        .font(.title2).foregroundColor(.secondary).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("未检测到 DJI 设备").font(.subheadline).fontWeight(.semibold)
                        Text("请连接 Pocket 3/4、360 全景相机或插入 TF/SD 存储卡")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(8).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(8)
            } else {
                ForEach(detector.connectedDevices) { dev in
                    storageVolumeCard(for: dev)
                }
            }
        }
    }

    private func storageVolumeCard(for dev: ConnectedDevice) -> some View {
        let isSD = dev.volumeName.uppercased().contains("SD") || dev.volumeName.uppercased().contains("CARD")
        let result = volumeScanResults[dev.id]
        
        return HStack(spacing: 10) {
            Image(systemName: isSD ? "sdcard.fill" : "internaldrive.fill")
                .font(.title2).foregroundColor(isSD ? .green : .blue).frame(width: 26)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(dev.displayName).font(.system(size: 12, weight: .semibold))
                    Text(isSD ? "外置存储卡" : "机身存储")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(isSD ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                        .foregroundColor(isSD ? .green : .blue).cornerRadius(3)
                }
                Text(dev.volumeURL.path)
                    .font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if isScanning {
                    ProgressView().scaleEffect(0.6)
                } else if let res = result {
                    Text("\(res.items.count) 个素材").font(.system(size: 11, weight: .semibold))
                    Text(formattedBytes(res.totalSizeBytes)).font(.system(size: 10)).foregroundColor(.secondary)
                } else {
                    Text("等待扫描").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
        }
        .padding(7).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
    }

    // MARK: - 3. 媒体筛选工具栏

    private var mediaSelectionToolbar: some View {
        VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("素材清单").font(.caption).fontWeight(.semibold)
                    Text("已选 \(selectedItems.count) / \(allScannedItems.count) 项 (\(formattedBytes(selectedTotalBytes)))")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Button("全选") { selectAllItems() }.buttonStyle(.bordered).controlSize(.mini)
                    Button("全不选") { deselectAllItems() }.buttonStyle(.bordered).controlSize(.mini)
                    Button("仅待同步") { selectOnlyValidNewItems() }.buttonStyle(.bordered).controlSize(.mini)
                    Button("选已同步") { selectOnlyUploadedItems() }.buttonStyle(.bordered).controlSize(.mini)
                }
            }
            
            if !selectedDeletableItems.isEmpty || !allUploadedItems.isEmpty {
                HStack {
                    if !selectedDeletableItems.isEmpty {
                        Text("可清理勾选: \(selectedDeletableItems.count) 项 (\(formattedBytes(selectedDeletableItems.reduce(0) { $0 + $1.sizeBytes })))")
                            .font(.system(size: 9)).foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            deletionHelper.requestBatchDelete(items: selectedDeletableItems)
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "trash.fill")
                                Text("清理勾选 (\(selectedDeletableItems.count))")
                            }
                            .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.mini)
                    } else if !allUploadedItems.isEmpty && !uploadEngine.isUploading {
                        Text("已同步可清理: \(allUploadedItems.count) 项 (\(formattedBytes(allUploadedItems.reduce(0) { $0 + $1.sizeBytes })))")
                            .font(.system(size: 9)).foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            deletionHelper.requestBatchDelete(items: allUploadedItems)
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "trash")
                                Text("一键清理所有已同步 (\(allUploadedItems.count))")
                            }
                            .font(.system(size: 9))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
        }
    }

    // MARK: - 4. 素材清单列表

    private var mediaChecklistSection: some View {
        Group {
            if allScannedItems.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: isScanning ? "arrow.triangle.2.circlepath" : "photo.on.rectangle.angled")
                        .font(.title2).foregroundColor(.secondary)
                    Text(isScanning ? "正在扫描分析 DCIM 目录..." : "未发现待同步媒体文件")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).frame(height: 135)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4)).cornerRadius(6)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(allScannedItems) { item in
                            mediaItemRow(item)
                        }
                    }
                    .padding(3)
                }
                .frame(height: 140)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4)).cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
            }
        }
    }

    private func mediaItemRow(_ item: ScannedMediaItem) -> some View {
        let isSelected = selectedItemIds.contains(item.id)
        let isUploaded = uploadedItemIds.contains(item.id) || uploadEngine.completedItemIds.contains(item.id)
        let isCurrentlyUploading = (item.id == uploadEngine.currentUploadingItemId)
        let isPausedItem = uploadEngine.pausedItemIds.contains(item.id)
        let queueIndex = uploadEngine.queuedItemIds.firstIndex(of: item.id)
        
        let deviceName: String? = detector.connectedDevices.count > 1
            ? detector.connectedDevices.first(where: { item.fileURL.path.hasPrefix($0.volumeURL.path) })?.displayName
            : nil
        
        return HStack(spacing: 6) {
            // 列 1: 复选框 (固定宽度 18pt)
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { checked in
                    if checked { selectedItemIds.insert(item.id) }
                    else { selectedItemIds.remove(item.id) }
                }
            ))
            .toggleStyle(.checkbox).labelsHidden()
            .frame(width: 18)
            .disabled(uploadEngine.isUploading && (isCurrentlyUploading || queueIndex != nil || isPausedItem))
            
            // 列 2: 媒体图标 (固定宽度 16pt)
            Image(systemName: mediaIconName(for: item.kind))
                .font(.caption)
                .foregroundColor(item.isJunk ? .orange : (item.isCorrupt ? .red : .accentColor))
                .frame(width: 16)
            
            // 列 3: 文件名与日期/设备标签 (弹性伸缩，绝不挤压右侧固定列)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.filename)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack(spacing: 4) {
                    if let dev = deviceName {
                        Text("[\(dev)]").font(.system(size: 8, weight: .medium)).foregroundColor(.accentColor)
                    }
                    Text(formattedDate(item.creationDate)).font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 列 4: 状态徽章 (严格定宽 80pt，右对齐，100% 垂直笔直对齐)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if isCurrentlyUploading {
                    if uploadEngine.isPaused {
                        badgeTag(text: "⏸️ 已暂停", color: .orange)
                    } else {
                        let prog = Int((uploadEngine.currentProgress?.currentFileProgress ?? 0) * 100)
                        badgeTag(text: "🚀 传输 \(prog)%", color: .accentColor)
                    }
                } else if isPausedItem {
                    badgeTag(text: "⏸️ 已暂停", color: .orange)
                } else if let qIdx = queueIndex {
                    badgeTag(text: "⏳ 排队 #\(qIdx + 1)", color: .orange)
                } else if isUploaded {
                    badgeTag(text: "✅ 已同步", color: .green)
                } else if item.isCorrupt {
                    badgeTag(text: "损坏 0B", color: .red)
                } else if item.isJunk {
                    badgeTag(text: "疑似废片", color: .orange)
                } else {
                    badgeTag(text: "待同步", color: .blue)
                }
            }
            .frame(width: 80, alignment: .trailing)
            
            // 列 5: 行级操作按钮 (严格定宽 54pt，居中对齐；无操作时渲染透明占位防漂移)
            HStack(spacing: 0) {
                if isCurrentlyUploading && uploadEngine.isUploading {
                    Button(action: { uploadEngine.pauseCurrentItemAndProceedNext() }) {
                        Text("⏸️暂停").font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .foregroundColor(.orange)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                } else if isPausedItem && uploadEngine.isUploading {
                    Button(action: { uploadEngine.resumeItem(itemId: item.id) }) {
                        Text("▶️恢复").font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.green.opacity(0.18))
                            .foregroundColor(.green)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                } else if queueIndex != nil && uploadEngine.isUploading {
                    Button(action: { uploadEngine.prioritize(itemId: item.id, immediate: true) }) {
                        Text("⚡插队").font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .foregroundColor(.orange)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                } else if isUploaded || item.isJunk || item.isCorrupt {
                    Button(action: { deletionHelper.requestDelete(item: item) }) {
                        Text("🗑️删除").font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 54, height: 16)
                }
            }
            .frame(width: 54, alignment: .center)
            
            // 列 6: 文件大小 (严格定宽 62pt，右对齐，等宽数字字体)
            Text(formattedBytes(item.sizeBytes))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, 2).padding(.horizontal, 6)
        .background(isCurrentlyUploading ? Color.accentColor.opacity(0.12) : (isSelected ? Color.accentColor.opacity(0.06) : Color.clear))
        .cornerRadius(4)
    }

    private func badgeTag(text: String, color: Color) -> some View {
        Text(text).font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color.opacity(0.15)).foregroundColor(color).cornerRadius(3)
    }

    // MARK: - 5. 上传仪表盘与实时网速/ETA (Metrics Dashboard)

    private var metricsDashboardSection: some View {
        VStack(spacing: 6) {
            if uploadEngine.isUploading, let progress = uploadEngine.currentProgress {
                VStack(spacing: 6) {
                    HStack {
                        Text("[\(progress.currentFileIndex)/\(progress.totalFiles)] \(progress.currentFilename)")
                            .font(.caption2).fontWeight(.semibold).lineLimit(1)
                        Spacer()
                        Text("\(Int(progress.currentFileProgress * 100))%")
                            .font(.caption2).fontWeight(.bold).foregroundColor(.accentColor)
                    }
                    ProgressView(value: progress.currentFileProgress, total: 1.0).progressViewStyle(.linear)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        metricBox(title: "📹 视频进度", value: "\(progress.currentFileIndex) / \(progress.totalFiles) 个")
                        metricBox(title: "📊 总进度流量", value: "\(formattedBytes(progress.totalUploadedBytes)) / \(formattedBytes(progress.totalBytesToUpload)) (\(Int(progress.overallProgress * 100))%)")
                        metricBox(title: "⚡ 实时网速", value: formattedSpeed(progress.speedBytesPerSec))
                        metricBox(title: "⏱️ 预估剩余", value: formattedETA(progress.estimatedSecondsRemaining))
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "cup.and.saucer.fill").font(.system(size: 8)).foregroundColor(.orange)
                        Text("防休眠保护运行中 (屏幕可熄灭)").font(.system(size: 9)).foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 1)
                }
                .padding(8).background(Color.accentColor.opacity(0.06)).cornerRadius(6)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if let success = uploadSuccessMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text(success).font(.caption2).foregroundColor(.green)
                        }
                    } else if let err = uploadErrorMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                            Text(err).font(.caption2).foregroundColor(.red)
                        }
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("云端归档目标").font(.system(size: 9)).foregroundColor(.secondary)
                                Text(authManager.getTargetFolder())
                                    .font(.caption2).fontWeight(.medium).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("废片过滤阈值").font(.system(size: 9)).foregroundColor(.secondary)
                                Text("< \(authManager.getMinVideoSizeMB()) MB 自动排查")
                                    .font(.caption2).fontWeight(.medium)
                            }
                        }
                    }
                }
                .padding(8).background(Color(nsColor: .controlBackgroundColor).opacity(0.5)).cornerRadius(6)
            }
        }
    }

    private func metricBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9)).foregroundColor(.secondary)
            Text(value).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(4)
        .background(Color(nsColor: .controlBackgroundColor)).cornerRadius(4)
    }

    // MARK: - 6. 核心操作按钮 (严格手动启动，绝无自动开始)

    private var actionButtonGroup: some View {
        VStack(spacing: 6) {
            if uploadEngine.isUploading {
                HStack(spacing: 8) {
                    Button(role: .destructive, action: { uploadEngine.cancel() }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("取消全部")
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    
                    if uploadEngine.isPaused {
                        Button(action: { uploadEngine.resume() }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("继续上传")
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else {
                        Button(action: { uploadEngine.pause() }) {
                            HStack {
                                Image(systemName: "pause.fill")
                                Text("暂停")
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                Button(action: { startSyncSelectedItems() }) {
                    HStack {
                        Image(systemName: authManager.isAuthenticated ? "icloud.and.arrow.up.fill" : "key.fill")
                        Text(syncButtonTitle).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .disabled(allScannedItems.isEmpty || selectedItems.isEmpty || !authManager.isAuthenticated)
            }
        }
    }

    private var syncButtonTitle: String {
        if !authManager.isAuthenticated { return "请先连接 Google 账号以开启同步" }
        if detector.connectedDevices.isEmpty { return "请插入 DJI 设备" }
        if allScannedItems.isEmpty { return "当前无媒体文件可同步" }
        if selectedItems.isEmpty { return "请在上方列表中勾选要同步的文件" }
        return "🚀 开始同步选中的 \(selectedItems.count) 个素材 (共 \(formattedBytes(selectedTotalBytes)))"
    }

    // MARK: - 7. 底部辅助栏

    private var footerSection: some View {
        HStack {
            Button("偏好设置与 Google 账号...") { openPreferences() }
                .buttonStyle(.plain).font(.caption).foregroundColor(.secondary)
            Spacer()
            Button(action: scanDeviceManually) {
                Image(systemName: "arrow.clockwise").font(.caption)
                    .foregroundColor(isScanning ? .accentColor : .secondary)
            }
            .buttonStyle(.plain).disabled(isScanning || uploadEngine.isUploading)
            Spacer()
            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - 业务逻辑实现

    private func scanAllConnectedVolumes() async {
        isScanning = true
        defer { isScanning = false }
        
        let devices = detector.connectedDevices
        guard !devices.isEmpty else {
            await MainActor.run {
                self.volumeScanResults.removeAll()
                self.selectedItemIds.removeAll()
                self.uploadedItemIds.removeAll()
            }
            return
        }
        
        let minMB = authManager.getMinVideoSizeMB()
        let minBytes = Int64(minMB) * 1024 * 1024
        
        var newResults: [String: ScanResult] = [:]
        var newSelected = selectedItemIds
        var newUploadedIds: Set<String> = []
        
        for dev in devices {
            let res = await scanner.scan(dcimURL: dev.dcimURL, minVideoSizeBytes: minBytes)
            newResults[dev.id] = res
            
            for item in res.items {
                if await ledger.isUploaded(filename: item.filename, fileSize: item.sizeBytes) {
                    newUploadedIds.insert(item.id)
                }
                // 首次扫描到：默认勾选非废片、非损坏且尚未同步的健康素材
                if !selectedItemIds.contains(item.id) && !newUploadedIds.contains(item.id) && !item.isJunk && !item.isCorrupt {
                    newSelected.insert(item.id)
                }
            }
        }
        
        await MainActor.run {
            self.volumeScanResults = newResults
            self.selectedItemIds = newSelected
            self.uploadedItemIds = newUploadedIds
        }
    }

    private func selectAllItems() {
        for item in allScannedItems { selectedItemIds.insert(item.id) }
    }

    private func deselectAllItems() {
        selectedItemIds.removeAll()
    }

    private func selectOnlyValidNewItems() {
        selectedItemIds = Set(
            allScannedItems.filter {
                !uploadedItemIds.contains($0.id) && !uploadEngine.completedItemIds.contains($0.id) && !$0.isJunk && !$0.isCorrupt
            }.map(\.id)
        )
    }

    private func selectOnlyUploadedItems() {
        selectedItemIds = Set(
            allScannedItems.filter {
                uploadedItemIds.contains($0.id) || uploadEngine.completedItemIds.contains($0.id)
            }.map(\.id)
        )
    }

    private func excludeJunkItems() {
        for item in allScannedItems where item.isJunk || item.isCorrupt {
            selectedItemIds.remove(item.id)
        }
    }

    private func handleItemsDeleted(itemIds: Set<String>, freedBytes: Int64) {
        selectedItemIds.subtract(itemIds)
        uploadedItemIds.subtract(itemIds)
        
        for (devId, res) in volumeScanResults {
            let remaining = res.items.filter { !itemIds.contains($0.id) }
            let newTotal = remaining.reduce(0) { $0 + $1.sizeBytes }
            let newJunkCount = remaining.filter { $0.isJunk }.count
            let newJunkBytes = remaining.filter { $0.isJunk }.reduce(0) { $0 + $1.sizeBytes }
            volumeScanResults[devId] = ScanResult(
                items: remaining,
                totalSizeBytes: newTotal,
                ignoredCount: res.ignoredCount,
                ignoredSizeBytes: res.ignoredSizeBytes,
                junkCount: newJunkCount,
                junkSizeBytes: newJunkBytes,
                scanDurationSeconds: res.scanDurationSeconds
            )
        }
        
        self.uploadSuccessMessage = "🗑️ 成功释放 \(formattedBytes(freedBytes)) 相机存储空间！"
        
        Task {
            await scanAllConnectedVolumes()
        }
    }

    /// 严格由用户手动点击触发同步 (绝无插入自动开始)
    private func startSyncSelectedItems() {
        guard authManager.isAuthenticated else {
            openPreferences()
            return
        }
        let itemsToUpload = selectedItems
        guard !itemsToUpload.isEmpty, !uploadEngine.isUploading else { return }
        
        uploadErrorMessage = nil
        uploadSuccessMessage = nil
        
        Task {
            do {
                let result = try await uploadEngine.uploadItems(itemsToUpload)
                await MainActor.run {
                    self.uploadSuccessMessage = "🎉 同步完成！已上传 \(result.uploadedCount) 个，跳过 \(result.skippedCount) 个，传输流量 \(self.formattedBytes(result.totalBytesUploaded))。"
                    AppDelegate.sendNotification(
                        title: "DJIToDrive 素材同步完成",
                        body: "\(result.uploadedCount) 个素材 (\(self.formattedBytes(result.totalBytesUploaded))) 已导入 Google Drive！"
                    )
                }
                await scanAllConnectedVolumes()
            } catch {
                await MainActor.run {
                    if case UploadError.cancelled = error {
                        self.uploadErrorMessage = "上传已由用户取消。"
                    } else {
                        self.uploadErrorMessage = "上传失败: \(error.localizedDescription)"
                        AppDelegate.sendNotification(
                            title: "DJIToDrive 同步未完成",
                            body: "遇到问题: \(error.localizedDescription)"
                        )
                    }
                }
            }
        }
    }

    private func scanDeviceManually() {
        detector.scanExistingVolumes()
        Task { await scanAllConnectedVolumes() }
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
            backing: .buffered, defer: false
        )
        window.center()
        window.title = "DJIToDrive 偏好设置"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    private func loadAppIcon() -> NSImage? { AppFormatters.loadAppIcon() }
    private func mediaIconName(for kind: MediaKind) -> String { AppFormatters.mediaIconName(for: kind) }
    private func formattedDate(_ date: Date) -> String { AppFormatters.formattedDate(date) }
    private func formattedBytes(_ bytes: Int64) -> String { AppFormatters.formattedBytes(bytes) }
    private func formattedSpeed(_ bytesPerSec: Double) -> String { AppFormatters.formattedSpeed(bytesPerSec) }
    private func formattedETA(_ seconds: Double?) -> String { AppFormatters.formattedETA(seconds) }
}
