// ====================================
// 📁 文件职责：应用级生命周期管理、动态按需状态栏控制器与独立主窗口调度
// 包含：NSStatusItem 动态显隐（插卡显示/拔卡隐藏）、NSPopover 呼出、桌面双击独立窗口唤起
// 不包含：文件系统遍历与 Google Drive 传输细节
// 依赖：AppKit, SwiftUI, UserNotifications, DeviceDetector
// ====================================

import AppKit
import SwiftUI
import UserNotifications
import DeviceDetector

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var mainWindow: NSWindow?
    private let detector = DeviceDetector()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        setupPopover()
        setupNotifications()
        setupDeviceMonitoring()
        
        // 首次启动响应：若有 DJI 设备接入则展开气泡，无设备则呼出独立窗口
        if !detector.connectedDevices.isEmpty {
            showPopover()
        } else {
            showMainWindow()
        }
    }

    /// 响应用户在访达/桌面双击 DJIToDrive.app 图标，确保 100% 呼出界面
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let item = statusItem, item.isVisible, item.button != nil {
            togglePopover()
        } else {
            showMainWindow()
        }
        return true
    }

    private func setupNotifications() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 注册系统级标准 Edit 菜单，打通 macOS 键盘快捷键响应链 (Cmd+V, Cmd+C, Cmd+A, Cmd+Z)
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        editMenuItem.submenu = editMenu
        NSApplication.shared.mainMenu = mainMenu
    }

    // MARK: - 状态栏按需智能显隐 (Dynamic Status Bar Item)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            if let image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "DJIToDrive")?
                .withSymbolConfiguration(config) {
                button.image = image
            }
            button.title = " DJI"
            button.action = #selector(togglePopover)
            button.target = self
        }
        updateStatusItemVisibility()
    }

    private func setupDeviceMonitoring() {
        updateStatusItemVisibility()
        
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.detector.scanExistingVolumes()
                self?.updateStatusItemVisibility()
            }
        }
        
        workspaceCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.detector.scanExistingVolumes()
                self?.updateStatusItemVisibility()
            }
        }
    }

    /// 动态计算状态栏图标显隐：无设备时隐藏，有设备时浮现
    private func updateStatusItemVisibility() {
        let hasDevices = !detector.connectedDevices.isEmpty
        statusItem?.isVisible = hasDevices
        
        // 若设备拔除且 popover 正在展开，自动收拢
        if !hasDevices && popover?.isShown == true {
            popover?.performClose(nil)
        }
    }

    // MARK: - 弹出面板与独立窗口 (Popover & Window Management)

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 440, height: 600)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let popover = popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    public func showPopover() {
        guard let popover = popover, let item = statusItem, item.isVisible, let button = item.button else {
            showMainWindow()
            return
        }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    /// 呼出屏幕正中央的独立控制大窗口
    public func showMainWindow() {
        if let win = mainWindow, win.isVisible {
            win.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "DJIToDrive 控制中心"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MenuBarView())
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.mainWindow = window
    }

    public static func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 清理资源
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
