// ====================================
// 📁 文件职责：上传任务队列状态模型与调度辅助定义
// 包含：队列项状态枚举、抢占式插队参数、单文件完成与生命周期通知定义
// 不包含：网络流式切片传输具体实现
// 依赖：Foundation
// ====================================

import Foundation

extension Notification.Name {
    public static let djiSingleFileCompleted = Notification.Name("DJIToDriveSingleFileCompleted")
}

public struct SingleFileUploadOutcome: Sendable {
    public let cloudFileId: String
    public let isPreempted: Bool
    
    public init(cloudFileId: String, isPreempted: Bool) {
        self.cloudFileId = cloudFileId
        self.isPreempted = isPreempted
    }
}
