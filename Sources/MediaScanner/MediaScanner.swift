// ====================================
// 📁 文件职责：DCIM 目录深度遍历与媒体资产智能过滤引擎
// 包含：白名单资产收集（MP4/MOV/OSV/DNG/WAV/SRT）、.LRF/.THM 代理丢弃、文件尺寸与拍摄时间提取
// 不包含：硬件热插拔检测与云端断点续传
// 依赖：Foundation
// ====================================

import Foundation

/// 媒体资产大类
public enum MediaKind: String, Sendable, CaseIterable {
    case video = "主视频流 (4K/8K/360 .OSV/.MP4)"
    case rawPhoto = "RAW 照片 (DNG)"
    case jpegPhoto = "标准照片 (JPG)"
    case audioTrack = "专业独立音频 (DJI Mic 2 .WAV)"
    case subtitleMeta = "飞控/元数据字幕 (SRT)"
}

/// 扫描提取出的媒体项实体
public struct ScannedMediaItem: Identifiable, Sendable, Equatable {
    public var id: String { fileURL.path }
    public let filename: String
    public let fileURL: URL
    public let sizeBytes: Int64
    public let creationDate: Date
    public let kind: MediaKind
    public let isJunk: Bool
    public let isCorrupt: Bool
    public var isSelected: Bool
    
    public init(
        filename: String,
        fileURL: URL,
        sizeBytes: Int64,
        creationDate: Date,
        kind: MediaKind,
        isJunk: Bool = false,
        isCorrupt: Bool = false,
        isSelected: Bool = true
    ) {
        self.filename = filename
        self.fileURL = fileURL
        self.sizeBytes = sizeBytes
        self.creationDate = creationDate
        self.kind = kind
        self.isJunk = isJunk
        self.isCorrupt = isCorrupt
        self.isSelected = isSelected
    }
}

/// 扫描结果汇总报告
public struct ScanResult: Sendable {
    public let items: [ScannedMediaItem]
    public let totalSizeBytes: Int64
    public let ignoredCount: Int
    public let ignoredSizeBytes: Int64
    public let junkCount: Int
    public let junkSizeBytes: Int64
    public let scanDurationSeconds: Double
    
    public init(
        items: [ScannedMediaItem],
        totalSizeBytes: Int64,
        ignoredCount: Int,
        ignoredSizeBytes: Int64,
        junkCount: Int = 0,
        junkSizeBytes: Int64 = 0,
        scanDurationSeconds: Double
    ) {
        self.items = items
        self.totalSizeBytes = totalSizeBytes
        self.ignoredCount = ignoredCount
        self.ignoredSizeBytes = ignoredSizeBytes
        self.junkCount = junkCount
        self.junkSizeBytes = junkSizeBytes
        self.scanDurationSeconds = scanDurationSeconds
    }
    
    public static var empty: ScanResult {
        ScanResult(items: [], totalSizeBytes: 0, ignoredCount: 0, ignoredSizeBytes: 0, junkCount: 0, junkSizeBytes: 0, scanDurationSeconds: 0)
    }
}

/// 媒体扫描与过滤引擎
public final class MediaScanner: Sendable {
    
    // 允许同步上云的高价值素材白名单（小写，特别包含 360 相机专有 .osv 视频）
    private static let allowedVideoExtensions: Set<String> = ["mp4", "mov", "osv"]
    private static let allowedRawExtensions: Set<String> = ["dng"]
    private static let allowedPhotoExtensions: Set<String> = ["jpg", "jpeg"]
    private static let allowedAudioExtensions: Set<String> = ["wav"]
    private static let allowedSubtitleExtensions: Set<String> = ["srt"]
    
    // 硬性过滤丢弃的代理与系统缓存黑名单
    private static let blacklistedExtensions: Set<String> = ["lrf", "thm"]
    
    public init() {}
    
    /// 异步扫描指定的 DCIM 根目录并输出过滤结果（支持可配置废片大小过滤阈值）
    public func scan(dcimURL: URL, minVideoSizeBytes: Int64 = 10 * 1024 * 1024) async -> ScanResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(
            at: dcimURL,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return .empty
        }
        
        var validItems: [ScannedMediaItem] = []
        var totalValidSize: Int64 = 0
        var ignoredFileCount: Int = 0
        var ignoredTotalSize: Int64 = 0
        var junkFileCount: Int = 0
        var junkTotalSize: Int64 = 0
        
        while let fileURL = enumerator.nextObject() as? URL {
            // 排除 macOS 系统双元数据（如 ._DJI_0001.MP4）
            let filename = fileURL.lastPathComponent
            if filename.hasPrefix("._") || filename.hasPrefix(".") {
                ignoredFileCount += 1
                continue
            }
            
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }
            
            let ext = fileURL.pathExtension.lowercased()
            let fileSize = Int64(resourceValues.fileSize ?? 0)
            
            // 1. 命中黑名单（如 .LRF 预览低清视频），坚决剔除并统计节省的空间
            if Self.blacklistedExtensions.contains(ext) {
                ignoredFileCount += 1
                ignoredTotalSize += fileSize
                continue
            }
            
            // 2. 命中白名单，分类归档与智能排查
            if let kind = resolveMediaKind(forExtension: ext) {
                // 优先从 DJI/Osmo 文件名（例如 CAM_20260516142802_0001_D.OSV）精确解析拍摄时间
                let date = parseDateFromFilename(filename) ?? resourceValues.creationDate ?? resourceValues.contentModificationDate ?? Date()
                
                // 废片与损坏排查：0 字节判定损坏；主视频且小于设定阈值（如 <10MB）判定为误触废片
                let isCorrupt = (fileSize <= 0)
                let isJunkVideo = (kind == .video && fileSize < minVideoSizeBytes) || isCorrupt
                
                if isJunkVideo {
                    junkFileCount += 1
                    junkTotalSize += fileSize
                }
                
                let item = ScannedMediaItem(
                    filename: filename,
                    fileURL: fileURL,
                    sizeBytes: fileSize,
                    creationDate: date,
                    kind: kind,
                    isJunk: isJunkVideo,
                    isCorrupt: isCorrupt,
                    isSelected: !isJunkVideo // 废片默认取消勾选，有效素材默认勾选
                )
                validItems.append(item)
                totalValidSize += fileSize
            } else {
                // 未知非媒体文件过滤
                ignoredFileCount += 1
            }
        }
        
        // 按拍摄时间倒序排序（最新素材优先呈现）
        validItems.sort { $0.creationDate > $1.creationDate }
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        return ScanResult(
            items: validItems,
            totalSizeBytes: totalValidSize,
            ignoredCount: ignoredFileCount,
            ignoredSizeBytes: ignoredTotalSize,
            junkCount: junkFileCount,
            junkSizeBytes: junkTotalSize,
            scanDurationSeconds: elapsed
        )
    }
    
    private func resolveMediaKind(forExtension ext: String) -> MediaKind? {
        if Self.allowedVideoExtensions.contains(ext) {
            return .video
        }
        if Self.allowedRawExtensions.contains(ext) {
            return .rawPhoto
        }
        if Self.allowedPhotoExtensions.contains(ext) {
            return .jpegPhoto
        }
        if Self.allowedAudioExtensions.contains(ext) {
            return .audioTrack
        }
        if Self.allowedSubtitleExtensions.contains(ext) {
            return .subtitleMeta
        }
        return nil
    }
    
    /// 从诸如 CAM_20260516142802_0001_D.OSV 的标准命名中提取拍摄时间
    private func parseDateFromFilename(_ filename: String) -> Date? {
        let parts = filename.components(separatedBy: "_")
        if parts.count >= 2 {
            let candidate = parts[1]
            if candidate.count == 14 {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMddHHmmss"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                return formatter.date(from: candidate)
            }
        }
        return nil
    }
}
