import Cocoa
import Carbon

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    override init() {
        super.init()
        print("=== AppDelegate init called ===")
    }
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
    
    var statusItem: NSStatusItem?
    var eventHotKeyRef: EventHotKeyRef?
    var eventHandler: EventHandlerRef?
    var f19Pressed = false
    var globalMonitor: Any?
    var localMonitor: Any?
    var eventTap: CFMachPort?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("=== CapsC applicationDidFinishLaunching ===")
        setupStatusItem()
        requestAccessibilityPermissions()
        registerGlobalHotkey()
        print("=== CapsC finished launching ===")
    }
    
    func requestAccessibilityPermissions() {
        print("Checking accessibility permissions...")
        
        // First check without prompting
        let currentlyEnabled = AXIsProcessTrusted()
        print("Currently enabled: \(currentlyEnabled)")
        
        if !currentlyEnabled {
            print("Requesting accessibility permissions...")
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let accessEnabled = AXIsProcessTrustedWithOptions(options)
            print("After prompt - Access enabled: \(accessEnabled)")
            
            if !accessEnabled {
                print("⚠️ Please grant accessibility permissions manually")
                print("1. Go to: System Settings > Privacy & Security > Accessibility")
                print("2. Enable: CapsC")
                print("3. Restart the app")
            }
        } else {
            print("✅ Accessibility permissions already granted!")
        }
    }
    
    func setupStatusItem() {
        print("Setting up status item...")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.title = "C"
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit CapsC", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
        print("Status item setup complete")
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    func registerGlobalHotkey() {
        print("Registering F19+C hotkey using CGEvent tap...")
        
        // Create event tap to intercept key events
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                return appDelegate.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        if let eventTap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            print("Successfully created CGEvent tap for F19+C")
        } else {
            print("Failed to create event tap, falling back to NSEvent monitoring")
            fallbackToEventMonitoring()
        }
    }
    
    func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        if keyCode == 80 { // F19 key code
            if type == .keyDown {
                self.f19Pressed = true
                print("F19 pressed")
            } else if type == .keyUp {
                self.f19Pressed = false
                print("F19 released")
            }
            return Unmanaged.passUnretained(event) // Pass through F19 events
        } else if keyCode == 8 && type == .keyDown && self.f19Pressed { // C key code
            print("F19+C detected! Consuming event.")
            self.handleHotKeyPressed()
            return nil // Consume the C key event
        }
        
        return Unmanaged.passUnretained(event) // Pass through all other events
    }
    
    func fallbackToEventMonitoring() {
        print("Using fallback NSEvent monitoring...")
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            _ = self.handleKeyEvent(event)
        }
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            return self.handleKeyEvent(event)
        }
    }
    
    func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 80 { // F19 key code
            if event.type == .keyDown {
                self.f19Pressed = true
                print("F19 pressed")
            } else if event.type == .keyUp {
                self.f19Pressed = false
                print("F19 released")
            }
            return event
        } else if event.keyCode == 8 && event.type == .keyDown && self.f19Pressed { // C key code
            print("F19+C detected!")
            self.handleHotKeyPressed()
            return nil
        }
        return event
    }
    
    func handleHotKeyPressed() {
        activateChrome()
        cycleChromeTabs()
    }
    
    func activateChrome() {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        
        for app in runningApps {
            if app.bundleIdentifier == "com.google.Chrome" {
                app.activate(options: [.activateAllWindows])
                break
            }
        }
    }
    
    func cycleChromeTabs() {
        let script = """
            tell application "Google Chrome"
                if (count of windows) > 0 then
                    set currentWindow to front window
                    set windowCount to count of windows
                    set currentIndex to 1
                    
                    repeat with i from 1 to windowCount
                        if window i is currentWindow then
                            set currentIndex to i
                            exit repeat
                        end if
                    end repeat
                    
                    set nextIndex to currentIndex + 1
                    if nextIndex > windowCount then
                        set nextIndex to 1
                    end if
                    
                    set index of window nextIndex to 1
                    activate
                end if
            end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
            }
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
        if let eventHotKeyRef = eventHotKeyRef {
            UnregisterEventHotKey(eventHotKeyRef)
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