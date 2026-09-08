// ====================================
// 📁 文件职责：DJIToDrive 应用程序原生入口与 MainActor 调度
// 包含：@main 应用结构体、MainActor 静态主函数、NSApplication 生命周期启动
// 不包含：具体的 UI 绘制、网络传输与文件扫描
// 依赖：AppKit
// ====================================

import AppKit

@main
struct DJIToDriveApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // 配置为 Accessory 应用：常驻顶部菜单栏，不占用 Dock 图标与前台应用切换器
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
