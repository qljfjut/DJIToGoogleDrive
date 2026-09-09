// ====================================
// 📁 文件职责：SD 卡/相机存储素材物理删除与空间释放助手
// 包含：单文件彻底删除、伴随文件 (.LRF / .THM) 级联清除、批量删除已同步素材、安全确认弹窗状态与错误处理
// 不包含：UI 列表渲染与上传队列管理
// 依赖：Foundation, SwiftUI, MediaScanner
// ====================================

import Foundation
import SwiftUI
import MediaScanner

@MainActor
public final class MediaDeletionHelper: ObservableObject {
    @Published public var itemToDelete: ScannedMediaItem? = nil
    @Published public var itemsToBatchDelete: [ScannedMediaItem] = []
    
    @Published public var showSingleDeleteConfirm: Bool = false
    @Published public var showBatchDeleteConfirm: Bool = false
    @Published public var deleteErrorMessage: String? = nil
    @Published public var isDeleting: Bool = false

    public init() {}

    /// 请求删除单个素材 (触发确认框)
    public func requestDelete(item: ScannedMediaItem) {
        self.itemToDelete = item
        self.showSingleDeleteConfirm = true
    }

    /// 请求批量删除素材 (触发确认框)
    public func requestBatchDelete(items: [ScannedMediaItem]) {
        guard !items.isEmpty else { return }
        self.itemsToBatchDelete = items
        self.showBatchDeleteConfirm = true
    }

    /// 执行单个文件彻底删除，连带清除同名 .LRF 和 .THM 伴随缓存文件
    public func executeSingleDelete(
        item: ScannedMediaItem,
        onSuccess: @escaping (Int64) -> Void
    ) {
        let fileManager = FileManager.default
        var freedBytes = item.sizeBytes
        do {
            if fileManager.fileExists(atPath: item.fileURL.path) {
                try fileManager.removeItem(at: item.fileURL)
            }
            freedBytes += cleanCompanionFiles(for: item.fileURL)
            onSuccess(freedBytes)
        } catch {
            self.deleteErrorMessage = "删除文件失败: \(error.localizedDescription)"
        }
        self.itemToDelete = nil
    }

    /// 执行批量彻底删除
    public func executeBatchDelete(
        items: [ScannedMediaItem],
        onSuccess: @escaping (Int, Int64) -> Void
    ) {
        guard !items.isEmpty else { return }
        isDeleting = true
        defer {
            isDeleting = false
            self.itemsToBatchDelete = []
        }
        
        let fileManager = FileManager.default
        var deletedCount = 0
        var totalFreedBytes: Int64 = 0
        var lastError: Error?
        
        for item in items {
            do {
                if fileManager.fileExists(atPath: item.fileURL.path) {
                    try fileManager.removeItem(at: item.fileURL)
                    totalFreedBytes += item.sizeBytes
                    deletedCount += 1
                }
                totalFreedBytes += cleanCompanionFiles(for: item.fileURL)
            } catch {
                lastError = error
            }
        }
        
        if let err = lastError, deletedCount < items.count {
            self.deleteErrorMessage = "部分文件删除失败: \(err.localizedDescription)"
        }
        
        onSuccess(deletedCount, totalFreedBytes)
    }

    /// 级联清理相机生成的同名缓存伴随文件 (.LRF 低清文件 / .THM 缩略图)，返回释放的额外字节数
    private func cleanCompanionFiles(for fileURL: URL) -> Int64 {
        let fileManager = FileManager.default
        let parentDir = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        
        var freed: Int64 = 0
        let companionExtensions = ["lrf", "LRF", "thm", "THM"]
        for ext in companionExtensions {
            let compURL = parentDir.appendingPathComponent("\(baseName).\(ext)")
            if fileManager.fileExists(atPath: compURL.path) {
                if let attr = try? fileManager.attributesOfItem(atPath: compURL.path),
                   let size = attr[.size] as? Int64 {
                    freed += size
                }
                try? fileManager.removeItem(at: compURL)
            }
        }
        return freed
    }
}
