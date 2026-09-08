// ====================================
// 📁 文件职责：应用级生命周期管理与菜单栏 StatusItem 控制器
// 包含：NSStatusItem 实例化、NSPopover 弹出面板生命周期管理、启动后主动展开反馈
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
        
        // 启动后 0.3 秒主动弹出控制面板，给用户明确的双击启动交互反馈
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.showPopover()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            // 使用稳定兼容所有 macOS 版本的相机图标，并附加简短标识
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            if let image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "DJIToDrive")?
                .withSymbolConfiguration(config) {
                button.image = image
            } else {
                button.title = "📷 DJI"
            }
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
            showPopover()
        }
    }

    public func showPopover() {
        guard let popover = popover, let button = statusItem?.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 清理临时资源
    }
}
