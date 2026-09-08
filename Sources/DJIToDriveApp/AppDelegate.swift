// ====================================
// 📁 文件职责：应用级生命周期管理与菜单栏 StatusItem 控制器
// 包含：NSStatusItem 实例化、NSPopover 弹出面板生命周期管理、快捷点击事件处理
// 不包含：文件系统遍历与 Google Drive 传输细节
// 依赖：AppKit, SwiftUI
// ====================================

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            // 使用 macOS 原生 SF Symbol 图标表示相机与视频流状态
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = NSImage(systemSymbolName: "video.badge.waveform", accessibilityDescription: "DJIToDrive")?
                .withSymbolConfiguration(config)
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 420)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 清理临时资源与网络连接
    }
}
