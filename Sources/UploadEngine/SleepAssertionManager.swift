// ====================================
// 📁 文件职责：macOS 系统级防休眠断言管理器 (Power Sleep Assertion)
// 包含：上传期间防止系统闲置休眠 (PreventUserIdleSystemSleep)、允许显示器正常黑屏熄灭节能、上传完成/暂停/取消时安全释放断言
// 不包含：网络流传输与业务逻辑
// 依赖：Foundation
// ====================================

import Foundation

/// 线程安全的 macOS 原生防休眠断言管理器
public final class SleepAssertionManager: @unchecked Sendable {
    public static let shared = SleepAssertionManager()
    
    private var activityToken: (any NSObjectProtocol)?
    private let lock = NSLock()
    
    /// 当前是否正持有防休眠保护
    public var isAssertionActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activityToken != nil
    }
    
    private init() {}
    
    /// 激活防休眠保护：阻止 Mac 系统闲置休眠，同时允许屏幕正常熄灭节能
    public func activate(reason: String = "DJIToDrive 正在上传素材至 Google Drive") {
        lock.lock()
        defer { lock.unlock() }
        
        guard activityToken == nil else { return }
        
        // .idleSystemSleepDisabled: 阻止系统闲置休眠（屏幕根据系统设置仍可正常变暗或关闭熄灭）
        // .userInitiated: 声明此活动由用户显式触发，提升 I/O 调度权重防止 App Nap 扼流
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: reason
        )
    }
    
    /// 释放防休眠保护：将电源节能控制权还给 macOS
    public func deactivate() {
        lock.lock()
        defer { lock.unlock() }
        
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }
}
