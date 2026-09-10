// ====================================
// 📁 文件职责：DJIToGoogleDrive 原生多语言国际化管理中枢 (i18n & Localization)
// 包含：支持系统语言自适应、中英双语手动切换、响应式刷新驱动、全域文案字典
// 不包含：UI 绘制与业务网络传输
// 依赖：Foundation, SwiftUI
// ====================================

import Foundation
import SwiftUI

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case zhHans = "zh-Hans"
    case en = "en"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }
    
    public func localizedName(isEnglish: Bool) -> String {
        switch self {
        case .system: return isEnglish ? "System" : "跟随系统"
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }
}

@MainActor
public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()
    
    private let userDefaultsKey = "dji_to_drive_app_language"
    
    @Published public var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: userDefaultsKey)
        }
    }
    
    public var isEnglish: Bool {
        if currentLanguage == .en { return true }
        if currentLanguage == .zhHans { return false }
        // 跟随系统语言判定
        let prefLang = Locale.preferredLanguages.first?.lowercased() ?? "zh"
        return !prefLang.hasPrefix("zh")
    }
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
           let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            self.currentLanguage = .system
        }
    }
    
    // MARK: - 文案映射字典 (Type-safe localized strings)
    
    public var appName: String { "DJIToGoogleDrive" }
    
    public var googleDriveConnected: String {
        isEnglish ? "Google Drive Connected" : "Google Drive 已连接"
    }
    
    public var googleDriveNotConnected: String {
        isEnglish ? "Google Account Not Connected" : "Google 账号未连接"
    }
    
    public func storageReadyCount(_ count: Int) -> String {
        isEnglish ? "\(count) Storage Ready" : "\(count) 个存储就绪"
    }
    
    public var waitingConnection: String {
        isEnglish ? "Waiting for Device" : "等待连接"
    }
    
    public var noDeviceDetected: String {
        isEnglish ? "No DJI Device Detected" : "未检测到 DJI 设备"
    }
    
    public var noDeviceSubtext: String {
        isEnglish ? "Please connect Pocket 3/4, 360 camera, or insert SD card" : "请连接 Pocket 3/4、360 全景相机或插入 TF/SD 存储卡"
    }
    
    public var externalCard: String {
        isEnglish ? "SD Card" : "外置存储卡"
    }
    
    public var internalStorage: String {
        isEnglish ? "Internal Storage" : "机身存储"
    }
    
    public func mediaCount(_ count: Int) -> String {
        isEnglish ? "\(count) Items" : "\(count) 个素材"
    }
    
    public var waitingScan: String {
        isEnglish ? "Waiting to scan" : "等待扫描"
    }
    
    public var mediaChecklistTitle: String {
        isEnglish ? "Media Checklist" : "素材清单"
    }
    
    public func selectedItemsCount(_ selected: Int, total: Int, bytesStr: String) -> String {
        isEnglish ? "Selected \(selected) / \(total) (\(bytesStr))" : "已选 \(selected) / \(total) 项 (\(bytesStr))"
    }
    
    public var selectAll: String { isEnglish ? "Select All" : "全选" }
    public var deselectAll: String { isEnglish ? "Deselect" : "全不选" }
    public var onlyNewValid: String { isEnglish ? "New Only" : "仅待同步" }
    public var onlyUploaded: String { isEnglish ? "Synced" : "选已同步" }
    
    public func deletableCountLabel(_ count: Int, bytesStr: String) -> String {
        isEnglish ? "Cleanable: \(count) items (\(bytesStr))" : "可清理勾选: \(count) 项 (\(bytesStr))"
    }
    
    public func deleteSelectedBtn(_ count: Int) -> String {
        isEnglish ? "Clean Selected (\(count))" : "清理勾选 (\(count))"
    }
    
    public func deleteUploadedBtn(_ count: Int) -> String {
        isEnglish ? "Clean All Synced (\(count))" : "一键清理所有已同步 (\(count))"
    }
    
    public var scanningDCIM: String {
        isEnglish ? "Scanning DCIM folder..." : "正在扫描分析 DCIM 目录..."
    }
    
    public var noMediaFound: String {
        isEnglish ? "No pending media files found" : "未发现待同步媒体文件"
    }
    
    public var pauseBtn: String { isEnglish ? "⏸️Pause" : "⏸️暂停" }
    public var resumeBtn: String { isEnglish ? "▶️Resume" : "▶️恢复" }
    public var prioritizeBtn: String { isEnglish ? "⚡Jump" : "⚡插队" }
    public var deleteBtn: String { isEnglish ? "🗑️Delete" : "🗑️删除" }
    
    public var badgeUploading: String { isEnglish ? "🚀 Uploading" : "🚀 传输" }
    public var badgePaused: String { isEnglish ? "⏸️ Paused" : "⏸️ 已暂停" }
    public func badgeQueued(_ index: Int) -> String {
        isEnglish ? "⏳ Queue #\(index)" : "⏳ 排队 #\(index)"
    }
    public var badgeSynced: String { isEnglish ? "✅ Synced" : "✅ 已同步" }
    public var badgeCorrupt: String { isEnglish ? "Corrupt 0B" : "损坏 0B" }
    public var badgeJunk: String { isEnglish ? "Likely Junk" : "疑似废片" }
    public var badgePending: String { isEnglish ? "Pending" : "待同步" }
    
    public var videoProgressTitle: String { isEnglish ? "📹 Video Progress" : "📹 视频进度" }
    public var overallTrafficTitle: String { isEnglish ? "📊 Total Traffic" : "📊 总进度流量" }
    public var realTimeSpeedTitle: String { isEnglish ? "⚡ Real-time Speed" : "⚡ 实时网速" }
    public var estimatedRemainingTitle: String { isEnglish ? "⏱️ Remaining Time" : "⏱️ 预估剩余" }
    
    public var sleepProtectionActive: String {
        isEnglish ? "Sleep assertion active (display may sleep)" : "防休眠保护运行中 (屏幕可熄灭)"
    }
    
    public var cloudTargetFolder: String {
        isEnglish ? "Cloud Target Folder" : "云端归档目标"
    }
    
    public var junkFilterThreshold: String {
        isEnglish ? "Junk Video Filter" : "废片过滤阈值"
    }
    
    public func junkFilterDesc(_ mb: Int) -> String {
        isEnglish ? "< \(mb) MB auto-filter" : "< \(mb) MB 自动排查"
    }
    
    public var cancelAll: String { isEnglish ? "Cancel All" : "取消全部" }
    public var continueUpload: String { isEnglish ? "Resume Upload" : "继续上传" }
    public var pauseUpload: String { isEnglish ? "Pause" : "暂停" }
    
    public func startSyncTitle(count: Int, bytesStr: String) -> String {
        isEnglish ? "🚀 Start Syncing \(count) Items (\(bytesStr))" : "🚀 开始同步选中的 \(count) 个素材 (共 \(bytesStr))"
    }
    
    public var connectAccountFirst: String {
        isEnglish ? "Please connect Google account to start sync" : "请先连接 Google 账号以开启同步"
    }
    
    public var insertDeviceFirst: String {
        isEnglish ? "Please connect a DJI device" : "请插入 DJI 设备"
    }
    
    public var selectFilesFirst: String {
        isEnglish ? "Please select files to sync from the list" : "请在上方列表中勾选要同步的文件"
    }
    
    public var preferencesAndAccount: String {
        isEnglish ? "Preferences & Google Account..." : "偏好设置与 Google 账号..."
    }
    
    public var quit: String { isEnglish ? "Quit" : "退出" }
    
    public var singleDeleteConfirmTitle: String {
        isEnglish ? "Delete Media File Completely?" : "确认彻底删除素材？"
    }
    
    public func singleDeleteConfirmMsg(filename: String, sizeStr: String) -> String {
        isEnglish ? "File: \(filename)\nSize: \(sizeStr)\n\nThis will permanently delete the file from the SD card to free space. This cannot be undone!"
                  : "文件：\(filename)\n大小：\(sizeStr)\n\n该操作将直接从相机 SD 卡/存储中彻底删除该文件以释放空间，此操作不可撤销！"
    }
    
    public var batchDeleteConfirmTitle: String {
        isEnglish ? "Batch Clean Media Files?" : "确认批量清理素材？"
    }
    
    public func batchDeleteConfirmMsg(count: Int, sizeStr: String) -> String {
        isEnglish ? "This will permanently delete \(count) files from the SD card, reclaiming approx. \(sizeStr) of space!\n\nPlease make sure these files are safely backed up to Google Drive."
                  : "即将从相机 SD 卡中物理彻底删除 \(count) 个文件，预计释放 \(sizeStr) 空间！\n\n此操作不可撤销，请确认所选文件均已安全备份至 Google Drive。"
    }
    
    public var deleteConfirmAction: String { isEnglish ? "Delete Permanently" : "彻底删除" }
    public func batchDeleteAction(_ count: Int) -> String {
        isEnglish ? "Clean (\(count) files)" : "彻底清理 (\(count) 个文件)"
    }
    public var cancel: String { isEnglish ? "Cancel" : "取消" }
    
    public func freedSpaceToast(_ sizeStr: String) -> String {
        isEnglish ? "🗑️ Successfully freed \(sizeStr) on camera storage!" : "🗑️ 成功释放 \(sizeStr) 相机存储空间！"
    }
    
    public func syncCompletedToast(count: Int, skipped: Int, bytesStr: String) -> String {
        isEnglish ? "🎉 Sync Complete! Uploaded \(count), skipped \(skipped), transferred \(bytesStr)."
                  : "🎉 同步完成！已上传 \(count) 个，跳过 \(skipped) 个，传输流量 \(bytesStr)。"
    }
    
    // MARK: - 偏好设置与通用窗口文案
    public var preferencesTitle: String { isEnglish ? "Preferences" : "偏好设置" }
    public var controlCenterTitle: String { "DJIToGoogleDrive " + (isEnglish ? "Control Center" : "控制中心") }
    public var languageSetting: String { isEnglish ? "5. Display Language" : "5. 界面语言" }
    public var credentialsSection: String { isEnglish ? "2. Google Cloud Credentials" : "2. Google Cloud 凭证配置" }
    public var credentialsSubheader: String { isEnglish ? "All credentials are encrypted and stored via macOS Keychain" : "所有凭证均通过 macOS Keychain 硬件加密安全托管" }
    public var paste: String { isEnglish ? "Paste" : "粘贴" }
    public var saveToKeychain: String { isEnglish ? "Save Credentials to Keychain" : "保存凭证至 Keychain" }
    public var authStatusSection: String { isEnglish ? "3. Authorization Status" : "3. 账号授权状态" }
    public var connectedGoogleDrive: String { isEnglish ? "Connected to Google Drive" : "已成功连接 Google Drive" }
    public var notAuthorizedGoogleDrive: String { isEnglish ? "Google Account Not Authorized" : "尚未授权 Google 账号" }
    public func currentAccountLabel(_ email: String) -> String { isEnglish ? "Account: \(email)" : "当前账号: \(email)" }
    public var signOut: String { isEnglish ? "Sign Out" : "退出登录" }
    public var signInGoogle: String { isEnglish ? "Sign in with Google" : "立即登录 Google 账号" }
    public var openingBrowser: String { isEnglish ? "Opening browser..." : "正在打开浏览器..." }
    public var targetFolderSection: String { isEnglish ? "4. Google Drive Target Folder & Rules" : "4. Google Drive 目标目录与过滤规则" }
    public var targetFolderLabel: String { isEnglish ? "Target Directory (Folder name or Google Drive link/ID):" : "目标目录 (支持文件夹名称或直接粘贴 Google Drive 网址/ID):" }
    public var targetFolderPlaceholder: String { isEnglish ? "e.g.: DJI_Media or paste drive.google.com/drive/folders/..." : "例如: DJI_Media 或粘贴 drive.google.com/drive/folders/..." }
    public var createDateSubfolder: String { isEnglish ? "Create date subfolders (e.g.: Target/2026-09-09/)" : "按拍摄日期创建归档子目录 (例如: 目标目录/2026-09-09/)" }
    public var junkFilterThresholdLabel: String { isEnglish ? "Junk Video Threshold:" : "疑似废片过滤阈值:" }
    public var junkFilterExplanation: String { isEnglish ? "(Videos smaller than this are marked as junk and unselected)" : "(小于此大小的视频标记为废片并不默认勾选)" }
    public var saveTargetSettingsBtn: String { isEnglish ? "Save Target Folder & Filter Rules" : "保存目标目录与过滤配置" }
    public var credentialsSavedSuccess: String { isEnglish ? "✅ Credentials saved securely to Keychain!" : "✅ 凭证已安全固化保存（0600 本地保护）！" }
    public var targetSettingsSavedSuccess: String { isEnglish ? "✅ Target folder and filter rules saved successfully!" : "✅ 目标目录与过滤规则已成功保存！" }
    public var helpGuide: String { isEnglish ? "Need credentials? Create free desktop OAuth credentials on Google Cloud Console." : "未创建凭证？可前往 Google Cloud Console 免费创建桌面 OAuth 凭据。" }
    public var viewGuide: String { isEnglish ? "View Guide" : "查看指引" }
    
    // MARK: - 软件更新文案 (Software Update)
    public var softwareUpdateSection: String { isEnglish ? "1. Software Update & Version" : "1. 软件更新与版本" }
    public var viewCurrentVersionNotesBtn: String { isEnglish ? "What's New" : "本版更新亮点" }
    public var currentVersionLabel: String { isEnglish ? "Current Version:" : "当前版本:" }
    public var checkForUpdatesBtn: String { isEnglish ? "Check for Updates" : "检查更新" }
    public var checkingForUpdates: String { isEnglish ? "Checking for updates..." : "正在检查更新..." }
    public var alreadyLatestVersion: String { isEnglish ? "✅ You are up to date!" : "✅ 当前已是最新版本！" }
    public func newVersionAvailable(_ version: String) -> String {
        isEnglish ? "🎉 New version \(version) available!" : "🎉 发现新版本 \(version)！"
    }
    public var downloadUpdateBtn: String { isEnglish ? "View & Download on GitHub" : "前往 GitHub 查看并下载" }
    public var updateCheckFailed: String { isEnglish ? "Failed to connect to GitHub. Please check network/proxy." : "无法连接至 GitHub，请检查网络或代理后重试。" }
    public var oneClickUpdateBtn: String { isEnglish ? "🚀 Update & Restart" : "🚀 一键自动更新并重启" }
    public var manualDownloadLink: String { isEnglish ? "Manual Download (GitHub)" : "手动在浏览器下载" }
    public var downloadingUpdate: String { isEnglish ? "Downloading update..." : "正在下载更新包..." }
    public var installingAndRestarting: String { isEnglish ? "Installing & Restarting..." : "下载完成，正在自动安装并重启..." }
    public var downloadFailed: String { isEnglish ? "Download failed. Please check network or download manually." : "下载失败，请检查网络或点击手动下载通道。" }
    public var currentVersionNotesTitle: String { isEnglish ? "✨ What's New in This Version (v1.2.2)" : "✨ 本版本核心更新内容 (v1.2.2)" }
    public var currentVersionHighlights: [String] {
        if isEnglish {
            return [
                "🛡️ Single App Icon Guarantee: Stealth build packaging into .build/ prevents duplicate icons in Launchpad",
                "📋 Reorganized Flow: Updates on top, cohesive Google account settings in middle, language below",
                "✨ On-Demand Version Card: Compact collapsible card with zero default footprint, unfolds on click",
                "🌐 Dedicated Language Row: Full-width segmented picker eliminating text truncation for English",
                "🎨 Clean & Unified UI: Removed duplicate internal headers and icons for consistent, clean typography"
            ]
        } else {
            return [
                "🛡️ 启动台双图标根治：引入 .build/ 隐身打包与自动消重守门员，启动台永远唯一单图标",
                "📋 偏好设置层级理顺：更新置顶，Google 账号服务流紧凑居中，语言设置下移",
                "✨ 更新亮点按需折叠：默认零垂直空间占用，轻量胶囊按钮点击原地展开与收起",
                "🌐 界面语言独立通栏：分段器独立另起一行并自适应通栏，彻底消除 English 截断切边",
                "🎨 视觉去噪去重：移除窗口内重复大标题与杂乱小图标，全篇统一纯文字标题规范"
            ]
        }
    }
}
