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

extension Notification.Name {
    public static let djiUploadLifecycleStateChanged = Notification.Name("DJIToDriveUploadLifecycleStateChanged")
}

public struct ResumableSessionRecord: Codable, Sendable {
    public let filePath: String
    public let fileSize: Int64
    public let sessionURIString: String
    public let destinationFolderId: String
    public let createdAt: Date
    
    public init(filePath: String, fileSize: Int64, sessionURIString: String, destinationFolderId: String, createdAt: Date = Date()) {
        self.filePath = filePath
        self.fileSize = fileSize
        self.sessionURIString = sessionURIString
        self.destinationFolderId = destinationFolderId
        self.createdAt = createdAt
    }
}

@MainActor
public final class UploadEngine: ObservableObject {
    private static let chunkSize: Int = 16 * 1024 * 1024 // 16MB 分片 (256KB 的 64 倍)
    private static let maxRetries: Int = 5
    private static let retryBaseDelaySeconds: Double = 2.0
    
    @Published public private(set) var isUploading: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var currentUploadingItemId: String? = nil
    @Published public private(set) var queuedItemIds: [String] = []
    @Published public private(set) var pausedItemIds: Set<String> = []
    @Published public private(set) var completedItemIds: Set<String> = []
    @Published public private(set) var currentProgress: UploadProgressState?
    
    private let ledger: Ledger
    private let authManager: AuthManager
    
    // 任务队列与抢占控制
    private var activeQueue: [ScannedMediaItem] = []
    private var allItemsMap: [String: ScannedMediaItem] = [:]
    private var shouldPreemptCurrentFile: Bool = false
    private var preemptionReason: PreemptionReason? = nil
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    
    // 缓存文件夹 ID：避免每个文件都向 Google 发起文件夹查询
    var folderIdCache: [String: String] = [:]
    private var isCancelled: Bool = false
    
    // 实时网速采样计算
    private var lastSampleTime: CFAbsoluteTime = 0
    private var lastSampleBytes: Int64 = 0
    private var currentSpeedBytesPerSec: Double = 0
    
    public init(ledger: Ledger = Ledger(), authManager: AuthManager? = nil) {
        self.ledger = ledger
        self.authManager = authManager ?? AuthManager.shared
    }
    
    public func pause() {
        guard isUploading, !isPaused else { return }
        isPaused = true
        SleepAssertionManager.shared.deactivate()
        NotificationCenter.default.post(name: .djiUploadLifecycleStateChanged, object: nil, userInfo: ["state": "paused"])
    }
    
    public func resume() {
        guard isUploading, isPaused else { return }
        isPaused = false
        SleepAssertionManager.shared.activate()
        NotificationCenter.default.post(name: .djiUploadLifecycleStateChanged, object: nil, userInfo: ["state": "uploading"])
        pauseContinuation?.resume()
        pauseContinuation = nil
    }
    
    public func cancel() {
        SleepAssertionManager.shared.deactivate()
        self.isCancelled = true
        self.isUploading = false
        self.isPaused = false
        self.pauseContinuation?.resume()
        self.pauseContinuation = nil
        self.currentUploadingItemId = nil
        self.activeQueue.removeAll()
        self.queuedItemIds.removeAll()
        self.pausedItemIds.removeAll()
        self.allItemsMap.removeAll()
        self.preemptionReason = nil
        NotificationCenter.default.post(name: .djiUploadLifecycleStateChanged, object: nil, userInfo: ["state": "idle"])
    }
    
    /// 调整排队项优先级；immediate 为 true 时触发安全让道抢占式插队
    public func prioritize(itemId: String, immediate: Bool = true) {
        guard let index = activeQueue.firstIndex(where: { $0.id == itemId }) else { return }
        let targetItem = activeQueue.remove(at: index)
        
        if immediate && currentUploadingItemId != nil {
            activeQueue.insert(targetItem, at: 0)
            queuedItemIds = activeQueue.map(\.id)
            preemptionReason = .jumpQueue(targetItemId: itemId)
            shouldPreemptCurrentFile = true
            if isPaused {
                resume()
            }
        } else {
            activeQueue.insert(targetItem, at: 0)
            queuedItemIds = activeQueue.map(\.id)
        }
    }

    /// 单独暂停当前正在上传的文件，安全保存断点并自动让出通道顺延至排队 #1 任务
    public func pauseCurrentItemAndProceedNext() {
        guard let currentId = currentUploadingItemId else { return }
        pausedItemIds.insert(currentId)
        preemptionReason = .pauseCurrent
        shouldPreemptCurrentFile = true
        if isPaused {
            resume()
        }
    }

    /// 恢复已暂停的文件，重新插回队列首位接续断点上传
    public func resumeItem(itemId: String) {
        pausedItemIds.remove(itemId)
        guard let item = allItemsMap[itemId] else { return }
        
        if currentUploadingItemId != nil {
            activeQueue.insert(item, at: 0)
            queuedItemIds = activeQueue.map(\.id)
            preemptionReason = .jumpQueue(targetItemId: itemId)
            shouldPreemptCurrentFile = true
            if isPaused {
                resume()
            }
        } else {
            activeQueue.insert(item, at: 0)
            queuedItemIds = activeQueue.map(\.id)
        }
    }

    /// 单独取消/跳过指定文件：若为当前文件则立即让道开启下一个
    public func cancelSingleItem(itemId: String) {
        pausedItemIds.remove(itemId)
        if itemId == currentUploadingItemId {
            preemptionReason = .skipCurrent
            shouldPreemptCurrentFile = true
            if isPaused {
                resume()
            }
        } else {
            activeQueue.removeAll { $0.id == itemId }
            queuedItemIds = activeQueue.map(\.id)
        }
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
        isPaused = false
        isUploading = true
        activeQueue = items
        queuedItemIds = items.map(\.id)
        currentUploadingItemId = nil
        completedItemIds.removeAll()
        allItemsMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        
        NotificationCenter.default.post(name: .djiUploadLifecycleStateChanged, object: nil, userInfo: ["state": "uploading"])
        SleepAssertionManager.shared.activate()
        defer {
            SleepAssertionManager.shared.deactivate()
            isUploading = false
            isPaused = false
            currentUploadingItemId = nil
            activeQueue.removeAll()
            queuedItemIds.removeAll()
            pausedItemIds.removeAll()
            allItemsMap.removeAll()
            preemptionReason = nil
            if isCancelled {
                NotificationCenter.default.post(name: .djiUploadLifecycleStateChanged, object: nil, userInfo: ["state": "idle"])
            }
        }
        
        let token = try await authManager.getValidAccessToken()
        let targetFolderInput = authManager.getTargetFolder()
        let rootFolderId = try await resolveTargetFolderId(from: targetFolderInput, token: token)
        let createDateSubfolder = authManager.getCreateDateSubfolder()
        
        let totalBytes = items.reduce(0) { $0 + $1.sizeBytes }
        var uploadedBytesSoFar: Int64 = 0
        var uploadedCount = 0
        var skippedCount = 0
        var actualUploadedBytes: Int64 = 0
        var processedFileCount = 0
        let totalItemsCount = items.count
        
        lastSampleTime = CFAbsoluteTimeGetCurrent()
        lastSampleBytes = 0
        currentSpeedBytesPerSec = 0
        
        // 云端对账文件清单缓存（FolderID -> [Filename: Size]）
        var cloudFilesCache: [String: [String: Int64]] = [:]
        
        while !activeQueue.isEmpty {
            if isCancelled { throw UploadError.cancelled }
            
            let item = activeQueue.removeFirst()
            queuedItemIds = activeQueue.map(\.id)
            currentUploadingItemId = item.id
            processedFileCount += 1
            
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
                completedItemIds.insert(item.id)
                NotificationCenter.default.post(
                    name: .djiSingleFileCompleted,
                    object: nil,
                    userInfo: ["itemId": item.id, "filename": item.filename, "fileSize": item.sizeBytes]
                )
                reportProgress(item: item, fileIndex: processedFileCount, totalFiles: totalItemsCount, overallUploaded: uploadedBytesSoFar, grandTotalBytes: totalBytes, onProgress: onProgress)
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
                completedItemIds.insert(item.id)
                NotificationCenter.default.post(
                    name: .djiSingleFileCompleted,
                    object: nil,
                    userInfo: ["itemId": item.id, "filename": item.filename, "fileSize": item.sizeBytes]
                )
                reportProgress(item: item, fileIndex: processedFileCount, totalFiles: totalItemsCount, overallUploaded: uploadedBytesSoFar, grandTotalBytes: totalBytes, onProgress: onProgress)
                continue
            }
            
            // 3. 执行单文件 16MB Chunk 断点续传
            let outcome = try await uploadSingleFile(
                item: item,
                parentFolderId: destinationFolderId,
                token: token,
                fileIndex: processedFileCount,
                totalFiles: totalItemsCount,
                baseUploadedBytes: uploadedBytesSoFar,
                grandTotalBytes: totalBytes,
                onProgress: onProgress
            )
            
            if outcome.isPreempted {
                if preemptionReason == .pauseCurrent {
                    // 用户单独暂停了当前文件：保留在 pausedItemIds 中，不重新塞入队列，自动顺延传输排队 #1
                } else if preemptionReason == .skipCurrent {
                    // 用户单独取消/跳过了当前文件：不重新塞入队列
                } else {
                    // 紧急任务插队让道：将原文件重新插回排队首位，等待插队任务完成后无缝断点续传
                    activeQueue.insert(item, at: 0)
                    queuedItemIds = activeQueue.map(\.id)
                }
                preemptionReason = nil
                processedFileCount -= 1
                continue
            }
            
            let cloudFileId = outcome.cloudFileId
            uploadedBytesSoFar += item.sizeBytes
            actualUploadedBytes += item.sizeBytes
            uploadedCount += 1
            completedItemIds.insert(item.id)
            
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
            
            // 实时广播单文件完成事件（触发 UI 行秒级变绿）
            NotificationCenter.default.post(
                name: .djiSingleFileCompleted,
                object: nil,
                userInfo: ["itemId": item.id, "filename": item.filename, "fileSize": item.sizeBytes]
            )
        }
        
        NotificationCenter.default.post(name: .djiUploadLifecycleStateChanged, object: nil, userInfo: ["state": "completed"])
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
    
    // MARK: - 跨拔插/跨进程断点会话持久化 (Cross-Session Persistence)
    
    private var resumableSessionsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("DJIToDrive", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("resumable_sessions.json")
    }
    
    private func loadResumableSessions() -> [String: ResumableSessionRecord] {
        guard let data = try? Data(contentsOf: resumableSessionsURL),
              let decoded = try? JSONDecoder().decode([String: ResumableSessionRecord].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    private func saveResumableSession(_ record: ResumableSessionRecord) {
        var sessions = loadResumableSessions()
        sessions[record.filePath] = record
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: resumableSessionsURL, options: .atomic)
        }
    }
    
    private func removeResumableSession(for filePath: String) {
        var sessions = loadResumableSessions()
        sessions.removeValue(forKey: filePath)
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: resumableSessionsURL, options: .atomic)
        }
    }
    
    /// 获取或恢复上传会话，并探测 Google 当前已接收的字节偏移量
    private func obtainSessionAndOffset(
        item: ScannedMediaItem,
        parentFolderId: String,
        token: String
    ) async throws -> (sessionURI: URL, startOffset: Int64, finishedFileId: String?) {
        let sessions = loadResumableSessions()
        if let existing = sessions[item.fileURL.path],
           existing.fileSize == item.sizeBytes,
           existing.destinationFolderId == parentFolderId,
           Date().timeIntervalSince(existing.createdAt) < 7 * 86400,
           let uri = URL(string: existing.sessionURIString) {
            
            // 向 Google 发送空包探活探测当前已收到的字节边界
            var probeRequest = URLRequest(url: uri)
            probeRequest.httpMethod = "PUT"
            probeRequest.setValue("bytes */\(item.sizeBytes)", forHTTPHeaderField: "Content-Range")
            probeRequest.setValue("0", forHTTPHeaderField: "Content-Length")
            
            if let (data, response) = try? await URLSession.shared.data(for: probeRequest),
               let http = response as? HTTPURLResponse {
                if http.statusCode == 308 {
                    if let rangeHeader = http.value(forHTTPHeaderField: "Range"),
                       let lastHyphen = rangeHeader.split(separator: "-").last,
                       let lastByteReceived = Int64(lastHyphen) {
                        let nextByte = lastByteReceived + 1
                        return (sessionURI: uri, startOffset: nextByte, finishedFileId: nil)
                    }
                    return (sessionURI: uri, startOffset: 0, finishedFileId: nil)
                } else if http.statusCode == 200 || http.statusCode == 201 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let id = json["id"] as? String {
                        removeResumableSession(for: item.fileURL.path)
                        return (sessionURI: uri, startOffset: item.sizeBytes, finishedFileId: id)
                    }
                }
            }
            removeResumableSession(for: item.fileURL.path)
        }
        
        let newURI = try await initResumableSession(
            filename: item.filename,
            fileSize: item.sizeBytes,
            mimeType: mimeType(for: item.fileURL.pathExtension),
            parentFolderId: parentFolderId,
            token: token
        )
        let record = ResumableSessionRecord(
            filePath: item.fileURL.path,
            fileSize: item.sizeBytes,
            sessionURIString: newURI.absoluteString,
            destinationFolderId: parentFolderId
        )
        saveResumableSession(record)
        return (sessionURI: newURI, startOffset: 0, finishedFileId: nil)
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
    ) async throws -> SingleFileUploadOutcome {
        let (sessionURI, initialOffset, completedId) = try await obtainSessionAndOffset(
            item: item,
            parentFolderId: parentFolderId,
            token: token
        )
        
        if let fileId = completedId {
            return SingleFileUploadOutcome(cloudFileId: fileId, isPreempted: false)
        }
        
        guard let handle = try? FileHandle(forReadingFrom: item.fileURL) else {
            throw UploadError.fileNotFound
        }
        defer { try? handle.close() }
        
        var uploadedForThisFile: Int64 = initialOffset
        let totalFileSize = item.sizeBytes
        
        while uploadedForThisFile < totalFileSize {
            if isCancelled { throw UploadError.cancelled }
            
            // 抢占插队检测：保存当前已传切片进度，安全退出并让位给紧急插队文件
            if shouldPreemptCurrentFile {
                shouldPreemptCurrentFile = false
                return SingleFileUploadOutcome(cloudFileId: "", isPreempted: true)
            }
            
            // 暂停检测与无损异步挂起：保持断点，0 CPU 0 网络等待继续唤醒
            if isPaused {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.pauseContinuation = continuation
                }
                if isCancelled { throw UploadError.cancelled }
                if shouldPreemptCurrentFile {
                    shouldPreemptCurrentFile = false
                    return SingleFileUploadOutcome(cloudFileId: "", isPreempted: true)
                }
            }
            
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
                removeResumableSession(for: item.fileURL.path)
                return SingleFileUploadOutcome(cloudFileId: fileId, isPreempted: false)
            }
        }
        
        removeResumableSession(for: item.fileURL.path)
        return SingleFileUploadOutcome(cloudFileId: "", isPreempted: false)
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
}

