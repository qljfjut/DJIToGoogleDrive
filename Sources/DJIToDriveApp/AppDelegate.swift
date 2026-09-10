// ====================================
// 📁 文件职责：应用级生命周期管理、灵动动态图标微动画与独立主窗口调度
// 包含：NSStatusItem 动态图标微交互（上传中相机/云箭头交替、就绪纯相机、完成对勾、未插卡隐身）、NSPopover 呼出、桌面双击独立大窗口唤起
// 不包含：文件系统遍历与 Google Drive 传输细节
// 依赖：AppKit, SwiftUI, UserNotifications, DeviceDetector, UploadEngine
// ====================================

import AppKit
import SwiftUI
import UserNotifications
import DeviceDetector
import UploadEngine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var mainWindow: NSWindow?
    private let detector = DeviceDetector()

    // 状态栏图标动画状态机
    private enum IconState {
        case disconnected
        case connectedIdle
        case uploading
        case completed
    }
    
    private var currentIconState: IconState = .disconnected
    private var animationTimer: Timer?
    private var animationFrameToggle: Bool = false
    private var revertToIdleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        setupPopover()
        setupNotifications()
        setupDeviceAndUploadMonitoring()
        
        // 首次启动响应：若有设备接入则展开气泡，无设备则呼出独立居中窗口
        if !detector.connectedDevices.isEmpty {
            showPopover()
        } else {
            showMainWindow()
        }
    }

    /// 响应用户在访达/桌面双击 DJIToGoogleDrive.app 图标，确保 100% 呼出界面
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

    // MARK: - 灵动状态栏动态微动画 (Dynamic Micro-Animation State Machine)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.title = "" // 纯粹极简，绝无文字干扰
            button.imagePosition = .imageOnly
            button.image = makeSymbolImage(name: "camera.fill")
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupDeviceAndUploadMonitoring() {
        detector.scanExistingVolumes()
        let hasDevices = !detector.connectedDevices.isEmpty
        updateIconState(to: hasDevices ? .connectedIdle : .disconnected)
        
        // 1. 监听设备物理插拔事件
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.detector.scanExistingVolumes()
                let connected = !self.detector.connectedDevices.isEmpty
                if connected && self.currentIconState != .uploading {
                    self.updateIconState(to: .connectedIdle)
                    
                    // 硬件插入触发系统横幅通知并自动展开控制面板
                    if let dev = self.detector.activeDevice ?? self.detector.connectedDevices.first {
                        let snText = dev.serialNumber.map { " [SN: \($0)]" } ?? ""
                        let title = "🔌 已识别 \(dev.deviceType.rawValue)\(snText)"
                        let body = "已就绪 (\(dev.volumeName))，点击展开控制中心开始同步至 Google Drive。"
                        AppDelegate.sendNotification(title: title, body: body)
                        self.showPopover()
                    }
                }
            }
        }
        
        workspaceCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.detector.scanExistingVolumes()
                let connected = !self.detector.connectedDevices.isEmpty
                if !connected {
                    self.updateIconState(to: .disconnected)
                }
            }
        }
        
        // 2. 监听上传生命周期广播（就绪 / 上传中 / 已完成）
        NotificationCenter.default.addObserver(
            forName: .djiUploadLifecycleStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let state = notification.userInfo?["state"] as? String
                if state == "uploading" {
                    self.updateIconState(to: .uploading)
                } else if state == "completed" {
                    self.updateIconState(to: .completed)
                } else {
                    let connected = !self.detector.connectedDevices.isEmpty
                    self.updateIconState(to: connected ? .connectedIdle : .disconnected)
                }
            }
        }
    }

    /// 核心图标状态机切换驱动（永久在线常驻，绝不隐形）
    private func updateIconState(to newState: IconState) {
        currentIconState = newState
        animationTimer?.invalidate()
        animationTimer = nil
        revertToIdleTimer?.invalidate()
        revertToIdleTimer = nil
        
        guard let button = statusItem?.button else { return }
        button.title = "" // 保持纯净无文字
        statusItem?.isVisible = true // 状态栏图标永久常驻可见
        
        switch newState {
        case .disconnected:
            button.image = makeSymbolImage(name: "camera")
            
        case .connectedIdle:
            button.image = makeSymbolImage(name: "camera.fill")
            
        case .uploading:
            animationFrameToggle = false
            button.image = makeSymbolImage(name: "arrow.up.circle.fill")
            
            // 启动 1.2 秒交替微动画：相机 <-> 上传云箭头
            animationTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.currentIconState == .uploading, let btn = self.statusItem?.button else { return }
                    self.animationFrameToggle.toggle()
                    let symbolName = self.animationFrameToggle ? "camera.fill" : "arrow.up.circle.fill"
                    btn.image = self.makeSymbolImage(name: symbolName)
                }
            }
            
        case .completed:
            button.image = makeSymbolImage(name: "checkmark.circle.fill")
            
            // 8 秒后平滑回归待命状态
            revertToIdleTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.currentIconState == .completed else { return }
                    let connected = !self.detector.connectedDevices.isEmpty
                    self.updateIconState(to: connected ? .connectedIdle : .disconnected)
                }
            }
        }
    }

    private func makeSymbolImage(name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "DJIToGoogleDrive")?.withSymbolConfiguration(config) else {
            return nil
        }
        let targetSize = NSSize(width: 18, height: 18)
        let canvas = NSImage(size: targetSize, flipped: false) { rect in
            let originX = (rect.width - symbol.size.width) / 2.0
            let originY = (rect.height - symbol.size.height) / 2.0
            let targetRect = NSRect(x: originX, y: originY, width: symbol.size.width, height: symbol.size.height)
            symbol.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        canvas.isTemplate = true
        return canvas
    }

    // MARK: - 弹出面板与独立窗口 (Popover & Window Management)

    private func setupPopover() {
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 440, height: 645)
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(rootView: MenuBarView())
        self.popover = pop
    }

    @objc private func togglePopover() {
        guard let pop = popover, let btn = statusItem?.button else { return }
        if pop.isShown {
            pop.performClose(nil)
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
            pop.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        }
    }

    public func showPopover() {
        guard let pop = popover, let btn = statusItem?.button, !pop.isShown else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        pop.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
    }

    /// 呼出屏幕正中央的独立控制大窗口
    public func showMainWindow() {
        if let win = mainWindow, win.isVisible {
            win.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 645),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = LocalizationManager.shared.controlCenterTitle
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
        animationTimer?.invalidate()
        revertToIdleTimer?.invalidate()
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
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            self.showPopover()
            self.showMainWindow()
        }
        completionHandler()
    }
}
