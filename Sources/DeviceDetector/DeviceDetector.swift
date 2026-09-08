// ====================================
// 📁 文件职责：物理卷盘监听与 DJI 硬件特征智能识别器
// 包含：NSWorkspace 卷盘挂载/卸载事件监听、Pocket 3/4 与 360 全景特征比对、设备列表状态发布
// 不包含：具体媒体文件深度遍历与云端网络传输
// 依赖：Foundation, AppKit
// ====================================

import Foundation
import AppKit

/// 支持的 DJI 硬件设备类型枚举
public enum DJIDeviceType: String, Sendable, CaseIterable {
    case pocket3 = "DJI Osmo Pocket 3"
    case pocket4 = "DJI Osmo Pocket 4"
    case dji360 = "DJI 360 全景相机"
    case genericDJI = "DJI 媒体设备 (读卡器/直连)"
}

/// 已识别并连接的硬件设备实体
public struct ConnectedDevice: Identifiable, Sendable, Equatable {
    public var id: String { volumeURL.path }
    public let volumeName: String
    public let deviceType: DJIDeviceType
    public let volumeURL: URL
    public let dcimURL: URL
    
    public init(volumeName: String, deviceType: DJIDeviceType, volumeURL: URL, dcimURL: URL) {
        self.volumeName = volumeName
        self.deviceType = deviceType
        self.volumeURL = volumeURL
        self.dcimURL = dcimURL
    }
}

/// 设备挂载监听器（主线程单例或 Observable 状态源）
@MainActor
public final class DeviceDetector: ObservableObject {
    @Published public private(set) var connectedDevices: [ConnectedDevice] = []
    @Published public private(set) var activeDevice: ConnectedDevice?
    
    // 标记为 nonisolated(unsafe) 以允许在非隔离的 deinit 中注销系统监听
    private nonisolated(unsafe) var mountObserver: NSObjectProtocol?
    private nonisolated(unsafe) var unmountObserver: NSObjectProtocol?
    
    public init() {
        startObserving()
        scanExistingVolumes()
    }
    
    deinit {
        let center = NSWorkspace.shared.notificationCenter
        if let observer = mountObserver {
            center.removeObserver(observer)
        }
        if let observer = unmountObserver {
            center.removeObserver(observer)
        }
    }
    
    // MARK: - 事件监听器 (Observers)
    
    private func startObserving() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        
        // 监听系统物理卷盘挂载事件（插入 TF 卡或 Type-C 直连）
        mountObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                    self.handleVolumeMounted(at: volumeURL)
                }
            }
        }
        
        // 监听卷盘卸载事件（拔卡或断开数据线）
        unmountObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                    self.handleVolumeUnmounted(at: volumeURL)
                }
            }
        }
    }
    
    // MARK: - 扫描与特征匹配 (Scan & Pattern Matching)
    
    /// 扫描当前已挂载在 /Volumes 下的所有卷盘
    public func scanExistingVolumes() {
        let fileManager = FileManager.default
        guard let volumeURLs = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey, .volumeIsRemovableKey],
            options: [.skipHiddenVolumes]
        ) else {
            return
        }
        
        var detected: [ConnectedDevice] = []
        for url in volumeURLs {
            if let device = inspectVolume(at: url) {
                detected.append(device)
            }
        }
        
        self.connectedDevices = detected
        self.activeDevice = detected.first
    }
    
    private func handleVolumeMounted(at url: URL) {
        if let device = inspectVolume(at: url) {
            if !connectedDevices.contains(where: { $0.id == device.id }) {
                connectedDevices.append(device)
                activeDevice = device
            }
        }
    }
    
    private func handleVolumeUnmounted(at url: URL) {
        connectedDevices.removeAll { $0.volumeURL.path == url.path }
        if activeDevice?.volumeURL.path == url.path {
            activeDevice = connectedDevices.first
        }
    }
    
    /// 检查指定卷盘是否符合 DJI 设备特征
    private func inspectVolume(at volumeURL: URL) -> ConnectedDevice? {
        let fileManager = FileManager.default
        let volumeName = volumeURL.lastPathComponent
        
        // 排除系统盘 Macintosh HD
        if volumeURL.path == "/" || volumeName.contains("Macintosh HD") {
            return nil
        }
        
        // 标准 DCIM 目录检测
        let dcimURL = volumeURL.appendingPathComponent("DCIM", isDirectory: true)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: dcimURL.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        
        // 深入分析 DCIM 内部特征以判定设备型号
        let type = classifyDeviceType(volumeName: volumeName, dcimURL: dcimURL)
        return ConnectedDevice(
            volumeName: volumeName,
            deviceType: type,
            volumeURL: volumeURL,
            dcimURL: dcimURL
        )
    }
    
    /// 依据卷标名与 DCIM 子目录特征分类设备
    private func classifyDeviceType(volumeName: String, dcimURL: URL) -> DJIDeviceType {
        let upperName = volumeName.uppercased()
        
        // 1. 卷标显式命中
        if upperName.contains("POCKET4") {
            return .pocket4
        }
        if upperName.contains("POCKET3") || upperName.contains("OSMO_POCKET") {
            return .pocket3
        }
        if upperName.contains("360") || upperName.contains("PANORAMA") {
            return .dji360
        }
        
        // 2. 检查 DCIM 子目录签名
        let fileManager = FileManager.default
        guard let subdirs = try? fileManager.contentsOfDirectory(atPath: dcimURL.path) else {
            return .genericDJI
        }
        
        for dir in subdirs {
            let upperDir = dir.uppercased()
            if upperDir.contains("PANORAMA") || upperDir.contains("360") {
                return .dji360
            }
            if upperDir.contains("100MEDIA") {
                let mediaPath = dcimURL.appendingPathComponent(dir)
                if let files = try? fileManager.contentsOfDirectory(atPath: mediaPath.path) {
                    if files.contains(where: { $0.hasPrefix("DJI_") }) {
                        return .pocket3 // 经典 Pocket 3 航拍结构
                    }
                }
            }
        }
        
        return .genericDJI
    }
}
