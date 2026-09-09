// ====================================
// 📁 文件职责：UploadEngine 云端目录管理、对账自愈与 MIME 辅助扩展
// 包含：Google Drive 目录树创建查询、目标路径解析、云端文件对账拉取与 MIME 映射
// 依赖：Foundation
// ====================================

import Foundation

extension UploadEngine {
    
    // MARK: - 目录管理 (Folder Hierarchy)
    
    func getOrCreateFolder(named name: String, parentId: String?, token: String) async throws -> String {
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
    
    func resolveTargetFolderId(from input: String, token: String) async throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "DJI_Media" {
            return try await getOrCreateFolder(named: "DJI_Media", parentId: nil, token: token)
        }
        
        // 1. 如果用户粘贴的是 Google Drive 完整链接
        if let range = trimmed.range(of: "folders/") {
            let sub = trimmed[range.upperBound...]
            let cleanId = String(sub.prefix { $0 != "?" && $0 != "&" && $0 != "/" })
            if !cleanId.isEmpty {
                return cleanId
            }
        }
        
        // 2. 如果符合 Google Drive 文件夹 ID 特征
        let idRegex = "^[a-zA-Z0-9_-]{25,45}$"
        if trimmed.range(of: idRegex, options: .regularExpression) != nil {
            return trimmed
        }
        
        // 3. 否则作为普通文件夹名称在根目录查找或创建
        return try await getOrCreateFolder(named: trimmed, parentId: nil, token: token)
    }
    
    /// 查询指定云端目录现存文件清单（文件名 -> 字节大小），用于反向对账自愈 (Cloud Reconciliation)
    func fetchCloudExistingFiles(in folderId: String, token: String) async -> [String: Int64] {
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
    
    func mimeType(for ext: String) -> String {
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
