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
    
    // MARK: - Lifecycle
    
    override init() {
        super.init()
        print("=== CapsC AppDelegate init ===")
    }
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("=== CapsC launching ===")
        
        setupStatusItem()
        setupHotkeyManager()
        checkAndRequestPermissions()
        
        print("=== CapsC launched successfully ===")
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        print("=== CapsC terminating ===")
        hotkeyManager.stopMonitoring()
    }
    
    // MARK: - Setup Methods
    
    private func setupStatusItem() {
        print("Setting up status item...")
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
        
        // Update status periodically
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.updateStatusMenu()
        }
        
        print("Status item setup complete")
    }
    
    private func setupHotkeyManager() {
        hotkeyManager.delegate = self
        
        // Simplified permission check (like old implementation)
        let hasPermissions = AXIsProcessTrusted()
        print("🔐 Accessibility permissions: \(hasPermissions)")
        
        if hasPermissions {
            print("🔐 Starting hotkey monitoring")
            hotkeyManager.startMonitoring()
            
        } else {
            print("🔐 No permissions - will retry after permission request")
            
            // Start monitoring after a delay to allow permission granting
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if AXIsProcessTrusted() {
                    print("🔐 Permissions granted, starting monitoring")
                    self.hotkeyManager.startMonitoring()
                }
            }
            
            // Keep checking for permissions periodically
            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { timer in
                if AXIsProcessTrusted() {
                    print("🔐 Permissions granted after retry, starting monitoring")
                    self.hotkeyManager.startMonitoring()
                    timer.invalidate()
                }
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func checkAndRequestPermissions() {
        if !permissionManager.isAccessibilityGranted {
            print("Accessibility permissions not granted, requesting...")
            permissionManager.requestPermissions()
        } else {
            print("✅ Accessibility permissions already granted")
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
        
        // Update status bar icon
        let hasPermissions = permissionManager.isAccessibilityGranted
        let chromeRunning = windowManager.isChromeRunning()
        
        if hasPermissions && chromeRunning {
            statusItem?.button?.title = "⚡"
        } else if hasPermissions {
            statusItem?.button?.title = "🔧"
        } else {
            statusItem?.button?.title = "⚠️"
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
                print("✅ Chrome cycling test completed")
            } catch {
                print("❌ Chrome cycling test failed: \(error)")
                
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Chrome Cycling Failed"
                    alert.informativeText = "Error: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
}

// MARK: - HotkeyManagerDelegate

extension AppDelegate {
    func hotkeyPressed() {
        print("🔥 Hotkey pressed! Cycling Chrome windows...")
        
        Task {
            do {
                try await windowManager.activateAndCycleChrome()
                print("✅ Chrome cycling completed successfully")
            } catch {
                print("❌ Chrome cycling failed: \(error)")
            }
        }
    }
}

func fourCharCode(_ string: String) -> FourCharCode {
    assert(string.count == 4, "String must be exactly 4 characters")
    var result: FourCharCode = 0
    for char in string.utf16 {
        result = (result << 8) + FourCharCode(char)
    }
    return result
}
