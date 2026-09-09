// ====================================
// 📁 文件职责：Google Drive 原生 16MB Chunk 断点续传引擎
// 包含：云端归档目录树动态维护、Resumable 会话建立、分片上传、断网退避重试与去重联动
// 不包含：本地卷盘硬件监听
// 依赖：Foundation, Ledger, AuthManager, MediaScanner
// ====================================

import Foundation
import Ledger
import AuthManager
import MediaScanner

public enum UploadError: LocalizedError, Sendable {
    case fileNotFound
    case failedToCreateSession(String)
    case chunkUploadFailed(Int, String)
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "本地源文件不存在或无法读取。"
        case .failedToCreateSession(let msg):
            return "初始化 Google Drive 上传会话失败: \(msg)"
        case .chunkUploadFailed(let status, let msg):
            return "分片上传失败 (状态码 \(status)): \(msg)"
        case .cancelled:
            return "上传已被用户主动取消。"
        }
    }
}

public struct UploadProgressState: Sendable {
    public let currentFilename: String
    public let currentFileIndex: Int
    public let totalFiles: Int
    public let currentFileProgress: Double
    public let totalUploadedBytes: Int64
    public let totalBytesToUpload: Int64
    public let overallProgress: Double
    public let speedBytesPerSec: Double
    public let estimatedSecondsRemaining: Double?
}

public struct UploadResult: Sendable {
    public let uploadedCount: Int
    public let skippedCount: Int
    public let totalBytesUploaded: Int64
    
    public init(uploadedCount: Int, skippedCount: Int, totalBytesUploaded: Int64) {
        self.uploadedCount = uploadedCount
        self.skippedCount = skippedCount
        self.totalBytesUploaded = totalBytesUploaded
    }
}

@MainActor
public final class UploadEngine: ObservableObject {
    private static let chunkSize: Int = 16 * 1024 * 1024 // 16MB 分片 (256KB 的 64 倍)
    private static let maxRetries: Int = 5
    private static let retryBaseDelaySeconds: Double = 2.0
    
    @Published public private(set) var isUploading: Bool = false
    @Published public private(set) var currentProgress: UploadProgressState?
    
    private let ledger: Ledger
    private let authManager: AuthManager
    
    // 缓存文件夹 ID：避免每个文件都向 Google 发起文件夹查询
    private var folderIdCache: [String: String] = [:]
    private var isCancelled: Bool = false
    
    // 实时网速采样计算
    private var lastSampleTime: CFAbsoluteTime = 0
    private var lastSampleBytes: Int64 = 0
    private var currentSpeedBytesPerSec: Double = 0
    
    public init(ledger: Ledger = Ledger(), authManager: AuthManager? = nil) {
        self.ledger = ledger
        self.authManager = authManager ?? AuthManager.shared
    }
    
    public func cancel() {
        self.isCancelled = true
        self.isUploading = false
    }
    
    // MARK: - 批量上传入口 (Batch Upload Entrypoint)
    
    @discardableResult
    public func uploadItems(
        _ items: [ScannedMediaItem],
        onProgress: (@Sendable (UploadProgressState) -> Void)? = nil
    ) async throws -> UploadResult {
        guard !items.isEmpty else {
            return UploadResult(uploadedCount: 0, skippedCount: 0, totalBytesUploaded: 0)
        }
        
        isCancelled = false
        isUploading = true
        defer { isUploading = false }
        
        let token = try await authManager.getValidAccessToken()
        let targetFolderInput = authManager.getTargetFolder()
        let rootFolderId = try await resolveTargetFolderId(from: targetFolderInput, token: token)
        let createDateSubfolder = authManager.getCreateDateSubfolder()
        
        let totalBytes = items.reduce(0) { $0 + $1.sizeBytes }
        var uploadedBytesSoFar: Int64 = 0
        var uploadedCount = 0
        var skippedCount = 0
        var actualUploadedBytes: Int64 = 0
        
        lastSampleTime = CFAbsoluteTimeGetCurrent()
        lastSampleBytes = 0
        currentSpeedBytesPerSec = 0
        
        // 云端对账文件清单缓存（FolderID -> [Filename: Size]）
        var cloudFilesCache: [String: [String: Int64]] = [:]
        
        for (index, item) in items.enumerated() {
            if isCancelled { throw UploadError.cancelled }
            
            // 确定当前文件的具体云端目标目录
            let destinationFolderId: String
            let cloudPathPrefix: String
            
            if createDateSubfolder {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let dateDirName = dateFormatter.string(from: item.creationDate)
                destinationFolderId = try await getOrCreateFolder(named: dateDirName, parentId: rootFolderId, token: token)
                cloudPathPrefix = "\(targetFolderInput)/\(dateDirName)"
            } else {
                destinationFolderId = rootFolderId
                cloudPathPrefix = targetFolderInput
            }
            
            let fingerprint = ledger.calculateFingerprint(for: item.fileURL, fileSize: item.sizeBytes)
            
            // 1. 本地账本指纹比对
            if let fp = fingerprint, await ledger.isUploaded(fingerprint: fp) {
                skippedCount += 1
                uploadedBytesSoFar += item.sizeBytes
                reportProgress(item: item, fileIndex: index + 1, totalFiles: items.count, overallUploaded: uploadedBytesSoFar, grandTotalBytes: totalBytes, onProgress: onProgress)
                continue
            }
            
            // 2. 云端反向对账自愈（本地账本误删/换电脑兜底防重）
            if cloudFilesCache[destinationFolderId] == nil {
                cloudFilesCache[destinationFolderId] = await fetchCloudExistingFiles(in: destinationFolderId, token: token)
            }
            if let cloudFiles = cloudFilesCache[destinationFolderId],
               let cloudSize = cloudFiles[item.filename],
               cloudSize == item.sizeBytes {
                // 云端已存在同名且字节大小完全一致的文件！自动自愈写入本地账本并跳过
                if let fp = fingerprint {
                    await ledger.recordUpload(
                        fingerprint: fp,
                        filename: item.filename,
                        fileSize: item.sizeBytes,
                        cloudFileId: "cloud_reconciled",
                        cloudPath: "\(cloudPathPrefix)/\(item.filename)"
                    )
                }
                skippedCount += 1
                uploadedBytesSoFar += item.sizeBytes
                reportProgress(item: item, fileIndex: index + 1, totalFiles: items.count, overallUploaded: uploadedBytesSoFar, grandTotalBytes: totalBytes, onProgress: onProgress)
                continue
            }
            
            // 3. 执行单文件 16MB Chunk 断点续传
            let cloudFileId = try await uploadSingleFile(
                item: item,
                parentFolderId: destinationFolderId,
                token: token,
                fileIndex: index + 1,
                totalFiles: items.count,
                baseUploadedBytes: uploadedBytesSoFar,
                grandTotalBytes: totalBytes,
                onProgress: onProgress
            )
            
            uploadedBytesSoFar += item.sizeBytes
            actualUploadedBytes += item.sizeBytes
            uploadedCount += 1
            
            // 4. 上传成功，固化至本地账本
            if let fp = fingerprint {
                await ledger.recordUpload(
                    fingerprint: fp,
                    filename: item.filename,
                    fileSize: item.sizeBytes,
                    cloudFileId: cloudFileId,
                    cloudPath: "\(cloudPathPrefix)/\(item.filename)"
                )
            }
        }
        
        return UploadResult(uploadedCount: uploadedCount, skippedCount: skippedCount, totalBytesUploaded: actualUploadedBytes)
    }
    
    private func reportProgress(
        item: ScannedMediaItem,
        fileIndex: Int,
        totalFiles: Int,
        overallUploaded: Int64,
        grandTotalBytes: Int64,
        onProgress: (@Sendable (UploadProgressState) -> Void)?
    ) {
        let overallProg = Double(overallUploaded) / Double(max(1, grandTotalBytes))
        let state = UploadProgressState(
            currentFilename: item.filename,
            currentFileIndex: fileIndex,
            totalFiles: totalFiles,
            currentFileProgress: 1.0,
            totalUploadedBytes: overallUploaded,
            totalBytesToUpload: grandTotalBytes,
            overallProgress: overallProg,
            speedBytesPerSec: currentSpeedBytesPerSec,
            estimatedSecondsRemaining: nil
        )
        self.currentProgress = state
        onProgress?(state)
    }
    
    // MARK: - 单文件分片上传 (Chunked Upload Engine)
    
    private func uploadSingleFile(
        item: ScannedMediaItem,
        parentFolderId: String,
        token: String,
        fileIndex: Int,
        totalFiles: Int,
        baseUploadedBytes: Int64,
        grandTotalBytes: Int64,
        onProgress: (@Sendable (UploadProgressState) -> Void)?
    ) async throws -> String {
        let sessionURI = try await initResumableSession(
            filename: item.filename,
            fileSize: item.sizeBytes,
            mimeType: mimeType(for: item.fileURL.pathExtension),
            parentFolderId: parentFolderId,
            token: token
        )
        
        guard let handle = try? FileHandle(forReadingFrom: item.fileURL) else {
            throw UploadError.fileNotFound
        }
        defer { try? handle.close() }
        
        var uploadedForThisFile: Int64 = 0
        let totalFileSize = item.sizeBytes
        
        while uploadedForThisFile < totalFileSize {
            if isCancelled { throw UploadError.cancelled }
            
            let currentChunkSize = Int(min(Int64(Self.chunkSize), totalFileSize - uploadedForThisFile))
            try handle.seek(toOffset: UInt64(uploadedForThisFile))
            
            guard let chunkData = try handle.read(upToCount: currentChunkSize) else {
                break
            }
            
            let rangeStart = uploadedForThisFile
            let rangeEnd = uploadedForThisFile + Int64(chunkData.count) - 1
            
            let resultId = try await uploadChunkWithRetry(
                sessionURI: sessionURI,
                chunkData: chunkData,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                totalSize: totalFileSize
            )
            
            uploadedForThisFile += Int64(chunkData.count)
            
            // 实时网速与剩余时间采样
            let now = CFAbsoluteTimeGetCurrent()
            let timeDelta = now - lastSampleTime
            let overallUploaded = baseUploadedBytes + uploadedForThisFile
            
            if timeDelta >= 0.8 {
                let bytesDelta = overallUploaded - lastSampleBytes
                if bytesDelta > 0 {
                    currentSpeedBytesPerSec = Double(bytesDelta) / timeDelta
                }
                lastSampleTime = now
                lastSampleBytes = overallUploaded
            }
            
            let remainingBytes = max(0, grandTotalBytes - overallUploaded)
            let etaSeconds: Double? = currentSpeedBytesPerSec > 1024 ? Double(remainingBytes) / currentSpeedBytesPerSec : nil
            
            let fileProgress = Double(uploadedForThisFile) / Double(max(1, totalFileSize))
            let overallProg = Double(overallUploaded) / Double(max(1, grandTotalBytes))
            
            let state = UploadProgressState(
                currentFilename: item.filename,
                currentFileIndex: fileIndex,
                totalFiles: totalFiles,
                currentFileProgress: fileProgress,
                totalUploadedBytes: overallUploaded,
                totalBytesToUpload: grandTotalBytes,
                overallProgress: overallProg,
                speedBytesPerSec: currentSpeedBytesPerSec,
                estimatedSecondsRemaining: etaSeconds
            )
            
            self.currentProgress = state
            onProgress?(state)
            
            if let fileId = resultId {
                return fileId
            }
        }
        
        return ""
    }
    
    private func uploadChunkWithRetry(
        sessionURI: URL,
        chunkData: Data,
        rangeStart: Int64,
        rangeEnd: Int64,
        totalSize: Int64
    ) async throws -> String? {
        var attempts = 0
        
        while attempts < Self.maxRetries {
            attempts += 1
            var request = URLRequest(url: sessionURI)
            request.httpMethod = "PUT"
            request.setValue("bytes \(rangeStart)-\(rangeEnd)/\(totalSize)", forHTTPHeaderField: "Content-Range")
            request.setValue("\(chunkData.count)", forHTTPHeaderField: "Content-Length")
            request.httpBody = chunkData
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw UploadError.chunkUploadFailed(-1, "无效响应")
                }
                
                if http.statusCode == 308 {
                    // 分片成功接收，继续下一片
                    return nil
                } else if http.statusCode == 200 || http.statusCode == 201 {
                    // 最后一个分片传完，解析最终的 Google Drive 文件 ID
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let id = json["id"] as? String {
                        return id
                    }
                    return ""
                } else {
                    let errStr = String(data: data, encoding: .utf8) ?? ""
                    if attempts >= Self.maxRetries {
                        throw UploadError.chunkUploadFailed(http.statusCode, errStr)
                    }
                }
            } catch {
                if attempts >= Self.maxRetries { throw error }
            }
            
            // 指数退避休眠重试
            let delay = Self.retryBaseDelaySeconds * pow(2.0, Double(attempts - 1))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        return nil
    }
    
    // MARK: - 会话初始化 (Initialize Resumable Session)
    
    private func initResumableSession(
        filename: String,
        fileSize: Int64,
        mimeType: String,
        parentFolderId: String,
        token: String
    ) async throws -> URL {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue("\(fileSize)", forHTTPHeaderField: "X-Upload-Content-Length")
        
        let metadata: [String: Any] = [
            "name": filename,
            "parents": [parentFolderId]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: metadata)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let location = http.value(forHTTPHeaderField: "Location"),
              let sessionURI = URL(string: location) else {
            let errText = String(data: data, encoding: .utf8) ?? "未知响应"
            throw UploadError.failedToCreateSession(errText)
        }
        
        return sessionURI
    }
    
    // MARK: - 目录管理 (Folder Hierarchy)
    
    private func getOrCreateFolder(named name: String, parentId: String?, token: String) async throws -> String {
        let cacheKey = "\(parentId ?? "root")/\(name)"
        if let cached = folderIdCache[cacheKey] {
            return cached
        }
        
        // 查询目录是否存在
        var query = "name = '\(name)' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        if let pid = parentId {
            query += " and '\(pid)' in parents"
        }
        
        var comp = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comp.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "fields", value: "files(id, name)")]
        
        var request = URLRequest(url: comp.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let files = json["files"] as? [[String: Any]],
           let first = files.first,
           let id = first["id"] as? String {
            folderIdCache[cacheKey] = id
            return id
        }
        
        // 目录不存在则动态创建
        var createReq = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        createReq.httpMethod = "POST"
        createReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var meta: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder"
        ]
        if let pid = parentId {
            meta["parents"] = [pid]
        }
        createReq.httpBody = try? JSONSerialization.data(withJSONObject: meta)
        
        let (createData, createRes) = try await URLSession.shared.data(for: createReq)
        if let http = createRes as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 201),
           let json = try? JSONSerialization.jsonObject(with: createData) as? [String: Any],
           let newId = json["id"] as? String {
            folderIdCache[cacheKey] = newId
            return newId
        }
        
        return "root"
    }
    
    // MARK: - 目标目录解析与云端反向对账自愈 (Reconciliation)
    
    private func resolveTargetFolderId(from input: String, token: String) async throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "DJI_Media" {
            return try await getOrCreateFolder(named: "DJI_Media", parentId: nil, token: token)
        }
        
        // 1. 如果用户粘贴的是 Google Drive 完整链接 (如 https://drive.google.com/drive/folders/1ABCxyz?usp=sharing)
        if let range = trimmed.range(of: "folders/") {
            let sub = trimmed[range.upperBound...]
            let cleanId = String(sub.prefix { $0 != "?" && $0 != "&" && $0 != "/" })
            if !cleanId.isEmpty {
                return cleanId
            }
        }
        
        // 2. 如果符合 Google Drive 文件夹 ID 特征 (25~45 位字母数字、下划线、减号)
        let idRegex = "^[a-zA-Z0-9_-]{25,45}$"
        if trimmed.range(of: idRegex, options: .regularExpression) != nil {
            return trimmed
        }
        
        // 3. 否则作为普通文件夹名称在根目录查找或创建
        return try await getOrCreateFolder(named: trimmed, parentId: nil, token: token)
    }
    
    /// 查询指定云端目录现存文件清单（文件名 -> 字节大小），用于反向对账自愈 (Cloud Reconciliation)
    private func fetchCloudExistingFiles(in folderId: String, token: String) async -> [String: Int64] {
        var result: [String: Int64] = [:]
        var comp = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let query = "'\(folderId)' in parents and trashed = false"
        comp.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id, name, size)"),
            URLQueryItem(name: "pageSize", value: "1000")
        ]
        
        guard let url = comp.url else { return result }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else {
            return result
        }
        
        for file in files {
            if let name = file["name"] as? String,
               let sizeStr = file["size"] as? String,
               let size = Int64(sizeStr) {
                result[name] = size
            }
        }
        
        return result
    }
    
    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "mp4", "osv": return "video/mp4"
        case "mov": return "video/quicktime"
        case "jpg", "jpeg": return "image/jpeg"
        case "dng": return "image/x-adobe-dng"
        case "wav": return "audio/wav"
        case "srt": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}
