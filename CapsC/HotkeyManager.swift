import Cocoa
import CoreGraphics
import OSLog
import Carbon

private let logger = Logger(subsystem: "net.kartar.CapsC", category: "HotkeyManager")

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyPressed()
}

class HotkeyManager: NSObject {
    
    weak var delegate: HotkeyManagerDelegate?
    
    // CGEvent tap approach
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // NSEvent monitor approach
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    
    // Carbon hotkey approach
    private var hotKeyRef: EventHotKeyRef?
    
    // Track Command key state
    private var commandKeyPressed = false
    
    override init() {
        super.init()
        logger.info("🔧 HotkeyManager initialized")
    }
    
    deinit {
        stopMonitoring()
    }
    
    func startMonitoring() {
        logger.info("🎯 Starting hotkey monitoring...")
        
        // Check accessibility permissions
        let trusted = AXIsProcessTrusted()
        logger.info("📱 AXIsProcessTrusted: \(trusted)")
        
        guard trusted else {
            logger.error("❌ Accessibility permissions not granted")
            return
        }
        
        // Try multiple approaches in order of preference
        
        // 1. First try NSEvent global monitor (works well for menu bar apps)
        startNSEventMonitoring()
        
        // 2. Then try Carbon Events as a more reliable fallback
        startCarbonHotKey()
        
        // 3. Finally try CGEventTap (might only get modifier keys)
        startCGEventTap()
    }
    
    func stopMonitoring() {
        logger.info("🛑 Stopping hotkey monitoring...")
        
        stopNSEventMonitoring()
        stopCarbonHotKey()
        stopCGEventTap()
        
        self.commandKeyPressed = false
        
        logger.info("✅ Hotkey monitoring stopped")
    }
    
    // MARK: - NSEvent Global Monitor Approach
    
    private func startNSEventMonitoring() {
        logger.info("🔧 Starting NSEvent global monitor...")
        
        // Monitor for key down events globally
        self.globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: NSEvent.EventTypeMask([.keyDown, .flagsChanged]),
            handler: { [weak self] (event: NSEvent) in
                guard let self = self else { return }
                
                if event.type == .flagsChanged {
                    self.commandKeyPressed = event.modifierFlags.contains(.command)
                    logger.debug("🚩 NSEvent: Command key \(self.commandKeyPressed ? "pressed" : "released")")
                } else if event.type == .keyDown {
                    logger.debug("🔍 NSEvent: keyDown - keyCode=\(event.keyCode), chars=\(event.characters ?? "nil")")
                    
                    // Check for Command-U
                    if event.keyCode == 32 && event.modifierFlags.contains(.command) {
                        logger.info("🔥 NSEvent: Command-U detected!")
                        DispatchQueue.main.async {
                            self.delegate?.hotkeyPressed()
                        }
                    }
                }
            })
        
        if globalEventMonitor != nil {
            logger.info("✅ NSEvent global monitor started")
        } else {
            logger.warning("⚠️ Failed to start NSEvent global monitor")
        }
    }
    
    private func stopNSEventMonitoring() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
    
    // MARK: - Carbon Events Approach (Most Reliable)
    
    private func startCarbonHotKey() {
        logger.info("🔧 Starting Carbon hotkey...")
        
        // Command-U: keyCode 32, cmdKey modifier
        let keyCode: UInt32 = 32  // U key
        let modifierFlags: UInt32 = UInt32(cmdKey)  // Command key
        
        // Create a unique ID for our hotkey
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("CAPC".fourCharCodeValue)
        hotKeyID.id = 1
        
        // Register the hotkey
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        // Install event handler
        let handler: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            logger.info("🔥 Carbon: Command-U hotkey pressed!")
            
            if let manager = userData {
                let self_ = Unmanaged<HotkeyManager>.fromOpaque(manager).takeUnretainedValue()
                DispatchQueue.main.async {
                    self_.delegate?.hotkeyPressed()
                }
            }
            
            return noErr
        }
        
        var eventHandler: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        
        // Register the hotkey
        let status = RegisterEventHotKey(keyCode, modifierFlags, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        if status == noErr {
            logger.info("✅ Carbon hotkey registered successfully")
        } else {
            logger.error("❌ Failed to register Carbon hotkey: \(status)")
        }
    }
    
    private func stopCarbonHotKey() {
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
        }
    }
    
    // MARK: - CGEventTap Approach (Fallback)
    
    private func startCGEventTap() {
        logger.info("🔧 Starting CGEventTap...")
        
        let eventMask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )
        
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo!).takeUnretainedValue()
            return manager.handleCGEvent(proxy: proxy, type: type, event: event)
        }
        
        // Try different tap locations
        let tapLocations: [(CGEventTapLocation, String)] = [
            (.cgAnnotatedSessionEventTap, "Annotated Session"),
            (.cgSessionEventTap, "Session"),
            (.cghidEventTap, "HID")
        ]
        
        for (location, name) in tapLocations {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) {
                self.eventTap = tap
                
                let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                self.runLoopSource = runLoopSource
                
                CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                
                logger.info("✅ CGEventTap created at location: \(name)")
                break
            }
        }
    }
    
    private func stopCGEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        self.eventTap = nil
        self.runLoopSource = nil
    }
    
    private func handleCGEvent(proxy: CGEventTapProxy?, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        logger.debug("📍 CGEvent: type=\(type.rawValue), keyCode=\(keyCode), flags=\(flags.rawValue)")
        
        switch type {
        case .flagsChanged:
            self.commandKeyPressed = flags.contains(.maskCommand)
            
        case .keyDown:
            if keyCode == 32 && self.commandKeyPressed {
                logger.info("🔥 CGEvent: Command-U detected!")
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyPressed()
                }
                return nil
            }
            
        default:
            break
        }
        
        return Unmanaged.passUnretained(event)
    }
}

// MARK: - Helper Extension

extension String {
    var fourCharCodeValue: UInt32 {
        guard self.count == 4 else { return 0 }
        var result: UInt32 = 0
        for char in self.utf16 {
            result = (result << 8) + UInt32(char)
        }
        return result
    }
}
