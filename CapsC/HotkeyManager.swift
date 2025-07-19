import Cocoa
import Carbon
import OSLog

private let logger = Logger(subsystem: "net.kartar.CapsC", category: "HotkeyManager")

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyPressed()
}

class HotkeyManager: NSObject {
    
    weak var delegate: HotkeyManagerDelegate?
    
    // Carbon hotkey approach (most reliable for menu bar apps)
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    
    override init() {
        super.init()
        if DebugConfig.debugMode {
            logger.info("🔧 HotkeyManager initialized")
        }
    }
    
    deinit {
        stopMonitoring()
    }
    
    func startMonitoring() {
        if DebugConfig.debugMode {
            logger.info("🎯 Starting hotkey monitoring...")
        }
        
        // Check accessibility permissions
        let trusted = AXIsProcessTrusted()
        if DebugConfig.debugMode {
            logger.info("📱 AXIsProcessTrusted: \(trusted)")
        }
        
        guard trusted else {
            if DebugConfig.debugMode {
                logger.error("❌ Accessibility permissions not granted")
            }
            return
        }
        
        // Use Carbon Events as the single, reliable approach
        startCarbonHotKey()
    }
    
    func stopMonitoring() {
        if DebugConfig.debugMode {
            logger.info("🛑 Stopping hotkey monitoring...")
        }
        
        stopCarbonHotKey()
        
        if DebugConfig.debugMode {
            logger.info("✅ Hotkey monitoring stopped")
        }
    }
    
    // MARK: - Carbon Events Approach
    
    private func startCarbonHotKey() {
        if DebugConfig.debugMode {
            logger.info("🔧 Starting Carbon hotkey...")
        }
        
        // Command-U: keyCode 32, cmdKey modifier
        let keyCode: UInt32 = 32  // U key
        let modifierFlags: UInt32 = UInt32(cmdKey)  // Command key
        
        // Create a unique ID for our hotkey
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("CAPC".fourCharCodeValue)
        hotKeyID.id = 1
        
        // Install event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            if DebugConfig.debugMode {
                logger.info("🔥 Carbon: Command-U hotkey pressed!")
            }
            
            if let manager = userData {
                let self_ = Unmanaged<HotkeyManager>.fromOpaque(manager).takeUnretainedValue()
                DispatchQueue.main.async {
                    self_.delegate?.hotkeyPressed()
                }
            }
            
            return noErr
        }
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        
        if status != noErr {
            if DebugConfig.debugMode {
                logger.error("❌ Failed to install event handler: \(status)")
            }
            return
        }
        
        // Register the hotkey
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if registerStatus == noErr {
            if DebugConfig.debugMode {
                logger.info("✅ Carbon hotkey registered successfully")
            }
        } else {
            if DebugConfig.debugMode {
                logger.error("❌ Failed to register Carbon hotkey: \(registerStatus)")
            }
        }
    }
    
    private func stopCarbonHotKey() {
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
        }
        
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
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