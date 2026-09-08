// ====================================
// 📁 文件职责：本地防重复上传指纹哈希账本
// 包含：复合指纹生成（首4MB+末4MB+字节总数）、JSON 账本持久化与防重查询
// 不包含：网络上传协议与硬件状态监听
// 依赖：Foundation, CryptoKit
// ====================================

import Foundation
import CryptoKit

/// 账本单条记录项
public struct LedgerEntry: Codable, Sendable, Equatable {
    public let fingerprint: String
    public let sourceFileName: String
    public let fileSize: Int64
    public let cloudFileId: String
    public let cloudPath: String
    public let uploadedAt: Date
    
    public init(
        fingerprint: String,
        sourceFileName: String,
        fileSize: Int64,
        cloudFileId: String,
        cloudPath: String,
        uploadedAt: Date = Date()
    ) {
        self.fingerprint = fingerprint
        self.sourceFileName = sourceFileName
        self.fileSize = fileSize
        self.cloudFileId = cloudFileId
        self.cloudPath = cloudPath
        self.uploadedAt = uploadedAt
    }
}

/// 增量去重账本（基于 Swift Actor 保证多任务读写安全）
public actor Ledger {
    private static let sampleChunkSize: Int = 4 * 1024 * 1024 // 首尾各采样 4MB
    private let storageURL: URL
    private var entries: [String: LedgerEntry] = [:]
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ledgerDir = appSupport.appendingPathComponent("DJIToDrive", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: ledgerDir, withIntermediateDirectories: true)
        self.storageURL = ledgerDir.appendingPathComponent("ledger.json")
        
        load()
    }
    
    // MARK: - 指纹生成 (Fingerprint Calculation)
    
    /// 针对 10GB~50GB+ 航拍巨型文件的高性能复合哈希算法（耗时仅数毫秒）
    public nonisolated func calculateFingerprint(for fileURL: URL, fileSize: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }
        
        var hasher = SHA256()
        
        // 1. 读取头部 4MB
        if let headData = try? handle.read(upToCount: Self.sampleChunkSize) {
            hasher.update(data: headData)
        }
        
        // 2. 若文件大于 8MB，定位并读取末尾 4MB
        let doubleSample = Int64(Self.sampleChunkSize * 2)
        if fileSize > doubleSample {
            let tailOffset = UInt64(fileSize - Int64(Self.sampleChunkSize))
            if (try? handle.seek(toOffset: tailOffset)) != nil {
                if let tailData = try? handle.read(upToCount: Self.sampleChunkSize) {
                    hasher.update(data: tailData)
                }
            }
        }
        
        // 3. 混入真实文件大小字节串防碰撞
        let sizePayload = "\(fileSize)".data(using: .utf8)!
        hasher.update(data: sizePayload)
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - 查询与记录 (Query & Mutation)
    
    /// 检查指定指纹是否已成功上传上云
    public func isUploaded(fingerprint: String) -> Bool {
        entries[fingerprint] != nil
    }
    
    /// 获取已上传文件的云端记录
    public func getEntry(fingerprint: String) -> LedgerEntry? {
        entries[fingerprint]
    }
    
    /// 写入成功上传记录并落盘
    public func recordUpload(
        fingerprint: String,
        filename: String,
        fileSize: Int64,
        cloudFileId: String,
        cloudPath: String
    ) {
        let entry = LedgerEntry(
            fingerprint: fingerprint,
            sourceFileName: filename,
            fileSize: fileSize,
            cloudFileId: cloudFileId,
            cloudPath: cloudPath,
            uploadedAt: Date()
        )
        entries[fingerprint] = entry
        save()
    }
    
    // MARK: - 持久化 (Persistence)
    
    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([String: LedgerEntry].self, from: data) else {
            return
        }
        self.entries = decoded
    }
    
    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(entries) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }
}
