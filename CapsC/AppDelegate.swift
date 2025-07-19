import Cocoa
import Combine

@main
class AppDelegate: NSObject, NSApplicationDelegate, HotkeyManagerDelegate {
    
    // MARK: - Manager Instances
    private let permissionManager = PermissionManager()
    private let hotkeyManager = HotkeyManager()
    private let windowManager = WindowManager()
    
    // MARK: - UI Components
    private var statusItem: NSStatusItem?
    
    // MARK: - Timers
    private var statusUpdateTimer: Timer?
    private var permissionCheckTimer: Timer?
    
    // MARK: - Lifecycle
    
    override init() {
        super.init()
        DebugConfig.log("AppDelegate", "=== CapsC AppDelegate init ===")
    }
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        DebugConfig.log("AppDelegate", "=== CapsC launching ===")
        
        setupStatusItem()
        setupHotkeyManager()
        checkAndRequestPermissions()
        
        DebugConfig.log("AppDelegate", "=== CapsC launched successfully ===")
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        DebugConfig.log("AppDelegate", "=== CapsC terminating ===")
        
        // Clean up timers
        statusUpdateTimer?.invalidate()
        permissionCheckTimer?.invalidate()
        
        // Stop hotkey monitoring
        hotkeyManager.stopMonitoring()
    }
    
    // MARK: - Setup Methods
    
    private func setupStatusItem() {
        DebugConfig.log("AppDelegate", "Setting up status item...")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.title = "⚡"
        
        let menu = NSMenu()
        
        // Chrome status info
        let chromeStatusItem = NSMenuItem(title: "Chrome: Checking...", action: nil, keyEquivalent: "")
        chromeStatusItem.isEnabled = false
        menu.addItem(chromeStatusItem)
        
        // Hotkey info
        let hotkeyItem = NSMenuItem(title: "Hotkey: ⌘U", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Permission status
        let permissionStatusItem = NSMenuItem(title: "Permissions: Checking...", action: nil, keyEquivalent: "")
        permissionStatusItem.isEnabled = false
        menu.addItem(permissionStatusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Actions
        menu.addItem(NSMenuItem(title: "Request Permissions", action: #selector(requestPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Test Chrome Cycling", action: #selector(testChromeCycling), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit CapsC", action: #selector(quit), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        
        // Single consolidated update timer
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.updateStatusMenu()
        }
        
        DebugConfig.log("AppDelegate", "Status item setup complete")
    }
    
    private func setupHotkeyManager() {
        hotkeyManager.delegate = self
        
        let hasPermissions = AXIsProcessTrusted()
        DebugConfig.log("AppDelegate", "🔐 Accessibility permissions: \(hasPermissions)")
        
        if hasPermissions {
            DebugConfig.log("AppDelegate", "🔐 Starting hotkey monitoring")
            hotkeyManager.startMonitoring()
        } else {
            DebugConfig.log("AppDelegate", "🔐 No permissions - will check periodically")
            startPermissionCheckTimer()
        }
    }
    
    private func startPermissionCheckTimer() {
        // Stop any existing timer
        permissionCheckTimer?.invalidate()
        
        // Check for permissions periodically
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { timer in
            if AXIsProcessTrusted() {
                DebugConfig.log("AppDelegate", "🔐 Permissions granted, starting monitoring")
                self.hotkeyManager.startMonitoring()
                timer.invalidate()
                self.permissionCheckTimer = nil
                
                // Show success notification
                self.showNotification(title: "CapsC Ready", 
                                    message: "Hotkey monitoring is now active. Press ⌘U to cycle Chrome windows.")
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func checkAndRequestPermissions() {
        if !permissionManager.isAccessibilityGranted {
            DebugConfig.log("AppDelegate", "Accessibility permissions not granted, requesting...")
            permissionManager.requestPermissions()
            
            // Show informative alert
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "CapsC Needs Accessibility Access"
                alert.informativeText = "To enable window cycling with ⌘U, please grant accessibility permissions in System Settings.\n\nAfter granting permission, CapsC will automatically start monitoring."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } else {
            DebugConfig.log("AppDelegate", "✅ Accessibility permissions already granted")
        }
    }
    
    private func updateStatusMenu() {
        guard let menu = statusItem?.menu else { return }
        
        // Update Chrome status
        if let chromeItem = menu.items.first {
            let isRunning = windowManager.isChromeRunning()
            let windowCount = windowManager.getChromeWindowCount()
            chromeItem.title = "Chrome: \(isRunning ? "Running (\(windowCount) windows)" : "Not Running")"
        }
        
        // Update permission status
        if menu.items.count > 3 {
            let permissionItem = menu.items[3]
            let hasPermissions = permissionManager.isAccessibilityGranted
            permissionItem.title = "Permissions: \(hasPermissions ? "✅ Granted" : "❌ Required")"
        }
        
        // Update status bar icon based on state
        updateStatusIcon()
    }
    
    private func updateStatusIcon() {
        let hasPermissions = permissionManager.isAccessibilityGranted
        let chromeRunning = windowManager.isChromeRunning()
        
        if hasPermissions && chromeRunning {
            statusItem?.button?.title = "⚡"  // Ready
        } else if hasPermissions {
            statusItem?.button?.title = "🔧"  // No Chrome
        } else {
            statusItem?.button?.title = "⚠️"   // No permissions
        }
    }
    
    private func showNotification(title: String, message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    private func showError(_ error: Error, context: String) {
        DebugConfig.log("AppDelegate", "❌ \(context): \(error)")
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Error: \(context)"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    // MARK: - Menu Actions
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func requestPermissions() {
        permissionManager.requestPermissions()
    }
    
    @objc private func testChromeCycling() {
        Task {
            do {
                try await windowManager.activateAndCycleChrome()
                DebugConfig.log("AppDelegate", "✅ Chrome cycling test completed")
            } catch {
                showError(error, context: "Chrome Cycling Test")
            }
        }
    }
}

// MARK: - HotkeyManagerDelegate

extension AppDelegate {
    func hotkeyPressed() {
        DebugConfig.log("AppDelegate", "🔥 Hotkey pressed! Cycling Chrome windows...")
        
        Task {
            do {
                try await windowManager.activateAndCycleChrome()
                DebugConfig.log("AppDelegate", "✅ Chrome cycling completed successfully")
            } catch {
                // For hotkey actions, show a less intrusive notification instead of alert
                let errorMessage: String
                if !windowManager.isChromeRunning() {
                    errorMessage = "Chrome is not running"
                } else if windowManager.getChromeWindowCount() == 0 {
                    errorMessage = "No Chrome windows found"
                } else {
                    errorMessage = error.localizedDescription
                }
                
                showNotification(title: "Window Cycling Failed", message: errorMessage)
                DebugConfig.log("AppDelegate", "❌ Chrome cycling failed: \(error)")
            }
        }
    }
}