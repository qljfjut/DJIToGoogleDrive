// ====================================
// 📁 文件职责：UI 呈现格式化工具集与媒体类型图标映射
// 包含：文件大小/网速/ETA/日期格式化、媒体图标映射、App 图标安全加载
// 不包含：业务状态管理与上传逻辑
// 依赖：Foundation, AppKit, MediaScanner
// ====================================

import Foundation
import AppKit
import MediaScanner

public enum AppFormatters {
    public static func formattedDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm"
        return df.string(from: date)
    }

    public static func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    public static func formattedSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec <= 0 { return "-- MB/s" }
        let mbPerSec = bytesPerSec / (1024.0 * 1024.0)
        return mbPerSec < 0.1 ? String(format: "%.1f KB/s", bytesPerSec / 1024.0) : String(format: "%.1f MB/s", mbPerSec)
    }

    public static func formattedETA(_ seconds: Double?) -> String {
        guard let sec = seconds, sec > 0, !sec.isInfinite, !sec.isNaN else { return "--" }
        let totalSec = Int(sec)
        let hours = totalSec / 3600
        let minutes = (totalSec % 3600) / 60
        let remainingSec = totalSec % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(remainingSec)s" }
        return "\(remainingSec)s"
    }

    public static func mediaIconName(for kind: MediaKind) -> String {
        switch kind {
        case .video: return "video.fill"
        case .rawPhoto: return "camera.macro"
        case .jpegPhoto: return "photo.fill"
        case .audioTrack: return "waveform"
        case .subtitleMeta: return "captions.bubble.fill"
        }
    }

    public static func loadAppIcon() -> NSImage? {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        return NSImage(named: NSImage.applicationIconName)
    }
}
