// ====================================
// 📁 文件职责：物理卷盘监听与 DJI 硬件特征智能识别器
// 包含：NSWorkspace 卷盘挂载/卸载事件监听、Pocket 3/4 与 360 全景特征比对、双卷盘智能优先级选择
// 不包含：具体媒体文件深度遍历与云端网络传输
// 依赖：Foundation, AppKit
// ====================================

import Foundation
import AppKit
import IOKit

/// 支持的 DJI 硬件设备类型枚举
public enum DJIDeviceType: String, Sendable, CaseIterable {
    case pocket3 = "DJI Osmo Pocket 3"
    case pocket4 = "DJI Osmo Pocket 4"
    case dji360 = "DJI Osmo 360"
    case action4 = "DJI Osmo Action 4"
    case action5 = "DJI Osmo Action 5 Pro"
    case action2 = "DJI Action 2"
    case genericDJI = "DJI 存储设备 (读卡器/直连)"
}

public struct DJIHwInfo: Sendable {
    public let deviceType: DJIDeviceType
    public let serialNumber: String?
}

/// 已识别并连接的硬件设备实体
public struct ConnectedDevice: Identifiable, Sendable, Equatable {
    public var id: String { volumeURL.path }
    public let volumeName: String
    public let deviceType: DJIDeviceType
    public let volumeURL: URL
    public let dcimURL: URL
    public let serialNumber: String?
    
    public var displayName: String {
        let upper = volumeName.uppercased()
        let snBadge = serialNumber != nil ? " [SN: \(serialNumber!)]" : ""
        if upper.contains("SD") || upper.contains("CARD") {
            return "\(deviceType.rawValue)\(snBadge) (存储卡)"
        } else if upper.contains("OSMO") || upper.contains("360") {
            return "\(deviceType.rawValue)\(snBadge) (机身存储)"
        }
        return "\(deviceType.rawValue)\(snBadge) (\(volumeName))"
    }
    
    public init(volumeName: String, deviceType: DJIDeviceType, volumeURL: URL, dcimURL: URL, serialNumber: String? = nil) {
        self.volumeName = volumeName
        self.deviceType = deviceType
        self.volumeURL = volumeURL
        self.dcimURL = dcimURL
        self.serialNumber = serialNumber
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
    
    /// 扫描当前已挂载在 /Volumes 下的所有卷盘，并自动优先选中包含实际素材的卷盘
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
        
        // 智能优先级排序：优先激活 DCIM 下有实际子文件内容的卷盘（解决双卷盘时误选空机身内置存储的问题）
        detected.sort { dev1, dev2 in
            let hasMedia1 = self.volumeContainsMedia(dcimURL: dev1.dcimURL)
            let hasMedia2 = self.volumeContainsMedia(dcimURL: dev2.dcimURL)
            if hasMedia1 != hasMedia2 {
                return hasMedia1 && !hasMedia2
            }
            return dev1.volumeName > dev2.volumeName
        }
        
        self.connectedDevices = detected
        self.activeDevice = detected.first
    }
    
    private func handleVolumeMounted(at url: URL) {
        if let device = inspectVolume(at: url) {
            if !connectedDevices.contains(where: { $0.id == device.id }) {
                connectedDevices.append(device)
            }
            // 重新重排优先级
            connectedDevices.sort { dev1, dev2 in
                let hasMedia1 = self.volumeContainsMedia(dcimURL: dev1.dcimURL)
                let hasMedia2 = self.volumeContainsMedia(dcimURL: dev2.dcimURL)
                if hasMedia1 != hasMedia2 {
                    return hasMedia1 && !hasMedia2
                }
                return dev1.volumeName > dev2.volumeName
            }
            self.activeDevice = connectedDevices.first
        }
    }
    
    private func handleVolumeUnmounted(at url: URL) {
        connectedDevices.removeAll { $0.volumeURL.path == url.path }
        if activeDevice?.volumeURL.path == url.path {
            activeDevice = connectedDevices.first
        }
    }
    
    /// 供外部显式切换当前活动卷盘
    public func selectDevice(_ device: ConnectedDevice) {
        if connectedDevices.contains(where: { $0.id == device.id }) {
            self.activeDevice = device
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
        
        // 深入结合 IOKit USB 硬件信息与 DCIM 内部特征以判定设备型号与设备号
        let hwInfo = Self.queryDJIHardware()
        let (type, sn) = classifyDeviceType(volumeName: volumeName, dcimURL: dcimURL, hwInfo: hwInfo)
        return ConnectedDevice(
            volumeName: volumeName,
            deviceType: type,
            volumeURL: volumeURL,
            dcimURL: dcimURL,
            serialNumber: sn
        )
    }
    
    /// 依据 IOKit 硬件描述符、卷标名与 DCIM 子目录特征精准分类设备并提取设备号
    private func classifyDeviceType(volumeName: String, dcimURL: URL, hwInfo: DJIHwInfo?) -> (DJIDeviceType, String?) {
        let upperName = volumeName.uppercased()
        
        if let hw = hwInfo {
            if upperName.contains("360") || upperName.contains("OSMO360") || hw.deviceType == .dji360 {
                return (.dji360, hw.serialNumber)
            }
            if upperName.contains("POCKET3") || upperName.contains("OSMO_POCKET") || hw.deviceType == .pocket3 {
                return (.pocket3, hw.serialNumber)
            }
            if upperName.contains("POCKET4") || hw.deviceType == .pocket4 {
                return (.pocket4, hw.serialNumber)
            }
            if upperName.contains("ACTION") || hw.deviceType == .action4 || hw.deviceType == .action5 {
                return (hw.deviceType, hw.serialNumber)
            }
            return (hw.deviceType, hw.serialNumber)
        }
        
        // 无 USB 硬件直连（如普通第三方 TF 读卡器插卡），依据卷标与 DCIM 特征精准识别官方学名
        if upperName.contains("POCKET4") { return (.pocket4, nil) }
        if upperName.contains("POCKET3") || upperName.contains("OSMO_POCKET") { return (.pocket3, nil) }
        if upperName.contains("360") || upperName.contains("PANORAMA") || upperName.contains("OSMO360") { return (.dji360, nil) }
        
        let fileManager = FileManager.default
        if let subdirs = try? fileManager.contentsOfDirectory(atPath: dcimURL.path) {
            for dir in subdirs {
                let upperDir = dir.uppercased()
                if upperDir.contains("PANORAMA") || upperDir.contains("360") || upperDir.hasPrefix("CAM_") {
                    return (.dji360, nil)
                }
                if upperDir.contains("100MEDIA") {
                    let mediaPath = dcimURL.appendingPathComponent(dir)
                    if let files = try? fileManager.contentsOfDirectory(atPath: mediaPath.path) {
                        if files.contains(where: { $0.hasPrefix("DJI_") }) {
                            return (.pocket3, nil)
                        }
                    }
                }
            }
        }
        
        return (.genericDJI, nil)
    }

    /// 通过 macOS 原生 IOKit 遍历 USB 总线，捕获大疆硬件出厂型号与序列号 (SN)
    public static func queryDJIHardware() -> DJIHwInfo? {
        let matchingDict = IOServiceMatching("IOUSBHostDevice")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            
            let vendor = IORegistryEntryCreateCFProperty(service, "idVendor" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
            let vendorName = IORegistryEntryCreateCFProperty(service, "USB Vendor Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            
            if vendor == 11427 || vendorName == "DJI" {
                let prod = (IORegistryEntryCreateCFProperty(service, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String)
                    ?? (IORegistryEntryCreateCFProperty(service, "kUSBProductString" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String)
                    ?? ""
                
                var sn: String? = nil
                if let snRange = prod.range(of: "SN:") {
                    let rawSn = String(prod[snRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !rawSn.isEmpty { sn = rawSn }
                }
                
                let upper = prod.uppercased()
                let type: DJIDeviceType
                if upper.contains("360") {
                    type = .dji360
                } else if upper.contains("POCKET4") {
                    type = .pocket4
                } else if upper.contains("POCKET3") {
                    type = .pocket3
                } else if upper.contains("ACTION5") {
                    type = .action5
                } else if upper.contains("ACTION4") {
                    type = .action4
                } else if upper.contains("ACTION2") {
                    type = .action2
                } else {
                    type = .genericDJI
                }
                return DJIHwInfo(deviceType: type, serialNumber: sn)
            }
        }
        return nil
    }
    
    /// 检查 DCIM 目录下是否存在子文件
    private func volumeContainsMedia(dcimURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard let subdirs = try? fileManager.contentsOfDirectory(atPath: dcimURL.path) else {
            return false
        }
        for sub in subdirs {
            let subURL = dcimURL.appendingPathComponent(sub)
            if let files = try? fileManager.contentsOfDirectory(atPath: subURL.path), !files.isEmpty {
                return true
            }
        }
        return false
    }
}
