// ====================================
// 📁 文件职责：GitHub Releases 远程版本自动检测器与 App 内部一键下载自更引擎
// 包含：异步请求 GitHub API、SemVer 比对、流式下载进度派发、ditto 原生解压与原子替换重启
// 不包含：业务上传逻辑
// 依赖：Foundation, AppKit
// ====================================

import Foundation
import AppKit

public struct ReleaseAsset: Codable, Sendable {
    public let name: String
    public let browserDownloadUrl: String
    public let size: Int64
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

public struct GitHubRelease: Codable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String
    public let publishedAt: String?
    public let assets: [ReleaseAsset]?
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

@MainActor
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()
    
    @Published public var isChecking: Bool = false
    @Published public var hasUpdate: Bool = false
    @Published public var latestRelease: GitHubRelease? = nil
    @Published public var statusMessage: String? = nil
    @Published public var lastCheckedDate: Date? = nil
    
    // 一键内联下载与安装状态
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var downloadStatus: String? = nil
    
    private let repoOwner = "qljfjut"
    private let repoName = "DJIToGoogleDrive"
    
    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
    }
    
    public init() {}
    
    /// 检查 GitHub Releases 是否有新版本发布
    public func checkForUpdates(manual: Bool = false) async {
        guard !isChecking, !isDownloading else { return }
        isChecking = true
        if manual {
            statusMessage = LocalizationManager.shared.checkingForUpdates
        }
        defer {
            isChecking = false
            lastCheckedDate = Date()
        }
        
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("DJIToGoogleDrive-App/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                if manual { statusMessage = LocalizationManager.shared.updateCheckFailed }
                return
            }
            
            guard http.statusCode == 200 else {
                if manual {
                    if http.statusCode == 404 {
                        statusMessage = LocalizationManager.shared.alreadyLatestVersion
                    } else {
                        statusMessage = LocalizationManager.shared.updateCheckFailed
                    }
                }
                return
            }
            
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            self.latestRelease = release
            
            let isNewer = compareVersions(remote: release.tagName, local: currentVersion)
            self.hasUpdate = isNewer
            
            if isNewer {
                self.statusMessage = LocalizationManager.shared.newVersionAvailable(release.tagName)
            } else {
                self.statusMessage = LocalizationManager.shared.alreadyLatestVersion
            }
        } catch {
            if manual {
                self.statusMessage = LocalizationManager.shared.updateCheckFailed
            }
        }
    }
    
    /// App 内一键静默自动下载更新包、ditto 解压、物理替换并平滑重启
    public func downloadAndInstallUpdate() async {
        guard !isDownloading else { return }
        guard let release = latestRelease,
              let asset = release.assets?.first(where: { $0.name.hasSuffix(".zip") && $0.name.contains("macOS") }) ?? release.assets?.first(where: { $0.name.hasSuffix(".zip") }),
              let downloadURL = URL(string: asset.browserDownloadUrl) else {
            openReleasePage()
            return
        }
        
        isDownloading = true
        downloadProgress = 0.0
        downloadStatus = LocalizationManager.shared.downloadingUpdate
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DJIToGoogleDrive_Update_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let zipPath = tempDir.appendingPathComponent("update.zip")
        
        do {
            var request = URLRequest(url: downloadURL)
            request.setValue("DJIToGoogleDrive-App/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            let expectedLength = response.expectedContentLength
            var data = Data()
            if expectedLength > 0 {
                data.reserveCapacity(Int(expectedLength))
            }
            
            var downloadedCount: Int64 = 0
            for try await byte in bytes {
                data.append(byte)
                downloadedCount += 1
                if expectedLength > 0 && downloadedCount % (256 * 1024) == 0 {
                    let progress = Double(downloadedCount) / Double(expectedLength)
                    await MainActor.run {
                        self.downloadProgress = progress
                    }
                }
            }
            
            try data.write(to: zipPath)
            
            await MainActor.run {
                self.downloadProgress = 1.0
                self.downloadStatus = LocalizationManager.shared.installingAndRestarting
            }
            
            // 使用 macOS 原生 ditto 无损解压
            let extractDir = tempDir.appendingPathComponent("extracted")
            try? FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
            
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzipProcess.arguments = ["-xk", zipPath.path, extractDir.path]
            try unzipProcess.run()
            unzipProcess.waitUntilExit()
            
            let appURL = extractDir.appendingPathComponent("DJIToGoogleDrive.app")
            guard FileManager.default.fileExists(atPath: appURL.path) else {
                throw NSError(domain: "UpdateChecker", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到解压出的应用程序文件"])
            }
            
            // 执行后台脱壳接力脚本：等待 0.8s 释放文件锁 ➔ 原子替换 /Applications ➔ 重新签署签名 ➔ 自动拉起新版
            let targetAppPath = "/Applications/DJIToGoogleDrive.app"
            let script = """
            sleep 0.8
            rm -rf "\(targetAppPath)"
            cp -R "\(appURL.path)" "\(targetAppPath)"
            xattr -cr "\(targetAppPath)"
            codesign --force --deep --sign - "\(targetAppPath)"
            open "\(targetAppPath)"
            """
            
            let swapProcess = Process()
            swapProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
            swapProcess.arguments = ["-c", script]
            try swapProcess.run()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            await MainActor.run {
                self.isDownloading = false
                self.downloadStatus = LocalizationManager.shared.downloadFailed
            }
        }
    }
    
    /// 浏览器打开 GitHub Release 下载页（备用通道）
    public func openReleasePage() {
        let target = latestRelease?.htmlUrl ?? "https://github.com/\(repoOwner)/\(repoName)/releases"
        if let url = URL(string: target) {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// 语义化版本比对：若 remote > local 返回 true
    private func compareVersions(remote: String, local: String) -> Bool {
        let cleanRemote = remote.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let cleanLocal = local.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        
        let remoteParts = cleanRemote.split(separator: ".").compactMap { Int($0) }
        let localParts = cleanLocal.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(remoteParts.count, localParts.count)
        for i in 0..<maxCount {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
