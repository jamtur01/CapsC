import Foundation
import Cocoa
import CoreGraphics

class WindowManager {
    
    init() {}
    
    func isChromeRunning() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == "com.google.Chrome" }
    }
    
    func getChromeWindowCount() -> Int {
        return getChromeWindows().count
    }
    
    func getChromeWindows() -> [ChromeWindow] {
        // Get windows with proper titles from Accessibility API
        var chromeWindows: [ChromeWindow] = []
        
        // First, find Chrome app
        let runningApps = NSWorkspace.shared.runningApplications
        guard let chromeApp = runningApps.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) else {
            DebugConfig.log("WindowManager", "🔍 Chrome not running")
            return []
        }
        
        let chromePID = chromeApp.processIdentifier
        
        // Use Accessibility API to get windows with proper titles
        guard AXIsProcessTrusted() else {
            DebugConfig.log("WindowManager", "❌ Process not trusted for accessibility")
            return []
        }
        
        let app = AXUIElementCreateApplication(chromePID)
        
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success,
              let axWindows = windowsRef as? [AXUIElement] else {
            DebugConfig.log("WindowManager", "❌ Failed to get windows from accessibility API")
            return []
        }
        
        // Get each window's details
        for (index, axWindow) in axWindows.enumerated() {
            var titleRef: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleResult == .success && titleRef != nil) ? (titleRef as? String ?? "Untitled") : "Untitled"
            
            var positionRef: CFTypeRef?
            let posResult = AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef)
            
            var sizeRef: CFTypeRef?
            let sizeResult = AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
            
            var position = CGPoint.zero
            var size = CGSize.zero
            
            if posResult == .success,
               let positionValue = positionRef,
               CFGetTypeID(positionValue) == AXValueGetTypeID() {
                AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
            }
            
            if sizeResult == .success,
               let sizeValue = sizeRef,
               CFGetTypeID(sizeValue) == AXValueGetTypeID() {
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            }
            
            var isMinimizedRef: CFTypeRef?
            let minResult = AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &isMinimizedRef)
            let isMinimized = (minResult == .success) ? (isMinimizedRef as? Bool ?? false) : false
            
            // Create a simple window ID based on index (since we can't get the real CGWindowID from accessibility API)
            let windowID = CGWindowID(index)
            
            let bounds: [String: Any] = [
                "X": position.x,
                "Y": position.y,
                "Width": size.width,
                "Height": size.height
            ]
            
            let window = ChromeWindow(
                id: windowID,
                title: title,
                ownerPID: chromePID,
                bounds: bounds,
                isMinimized: isMinimized,
                axWindow: axWindow
            )
            
            chromeWindows.append(window)
        }
        
        DebugConfig.log("WindowManager", "🔍 Found \(chromeWindows.count) Chrome windows")
        if DebugConfig.debugMode {
            for (index, window) in chromeWindows.enumerated() {
                let minimizedStatus = window.isMinimized ? " [MINIMIZED]" : ""
                DebugConfig.log("WindowManager", "  Window \(index): '\(window.title)' (ID: \(window.id))\(minimizedStatus)")
            }
        }
        
        return chromeWindows
    }
    
    func activateAndCycleChrome() async throws {
        DebugConfig.log("WindowManager", "🔄 Starting Chrome activation and cycling...")
        activateChrome()
        try await cycleChromeTabs()
    }
    
    private func activateChrome() {
        DebugConfig.log("WindowManager", "🚀 Activating Chrome...")
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        
        for app in runningApps {
            if app.bundleIdentifier == "com.google.Chrome" {
                DebugConfig.log("WindowManager", "✅ Found Chrome app, activating...")
                app.activate(options: [.activateAllWindows])
                break
            }
        }
    }
    
    private func cycleChromeTabs() async throws {
        DebugConfig.log("WindowManager", "🔄 Starting tab cycling...")
        let chromeWindows = getChromeWindows()
        
        guard !chromeWindows.isEmpty else {
            DebugConfig.log("WindowManager", "❌ No Chrome windows found!")
            throw NSError(domain: "WindowManagerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Chrome windows found"])
        }
        
        let frontmostWindow = getFrontmostChromeWindow(from: chromeWindows)
        if DebugConfig.debugMode {
            if let frontmost = frontmostWindow {
                DebugConfig.log("WindowManager", "👁️ Current frontmost window: '\(frontmost.title)' (ID: \(frontmost.id))")
            } else {
                DebugConfig.log("WindowManager", "⚠️ Could not determine frontmost window")
            }
        }
        
        let nextWindow = getNextChromeWindow(from: chromeWindows, after: frontmostWindow)
        DebugConfig.log("WindowManager", "➡️ Next window to focus: '\(nextWindow.title)' (ID: \(nextWindow.id))")
        
        try await bringWindowToFront(nextWindow)
    }
    
    private func getFrontmostChromeWindow(from windows: [ChromeWindow]) -> ChromeWindow? {
        DebugConfig.log("WindowManager", "🔍 Looking for frontmost Chrome window...")
        
        // Find the main (focused) window using Accessibility API
        for (index, window) in windows.enumerated() {
            guard let axWindow = window.axWindow else { continue }
            
            var isMainRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXMainAttribute as CFString, &isMainRef) == .success,
               let isMain = isMainRef as? Bool, isMain {
                DebugConfig.log("WindowManager", "✅ Found frontmost window at index \(index): '\(window.title)'")
                return window
            }
        }
        
        // If no main window found, return first non-minimized window
        if let firstVisible = windows.first(where: { !$0.isMinimized }) {
            DebugConfig.log("WindowManager", "⚠️ No main window found, returning first visible: '\(firstVisible.title)'")
            return firstVisible
        }
        
        // If all windows are minimized, return first
        DebugConfig.log("WindowManager", "⚠️ All windows minimized, returning first: '\(windows.first?.title ?? "none")'")
        return windows.first
    }
    
    private func getNextChromeWindow(from windows: [ChromeWindow], after currentWindow: ChromeWindow?) -> ChromeWindow {
        guard let currentWindow = currentWindow,
              let currentIndex = windows.firstIndex(where: { $0.id == currentWindow.id }) else {
            return windows.first!
        }
        
        let nextIndex = (currentIndex + 1) % windows.count
        return windows[nextIndex]
    }
    
    private func bringWindowToFront(_ window: ChromeWindow) async throws {
        DebugConfig.log("WindowManager", "🎯 Attempting to bring window '\(window.title)' to front...")
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                if let app = NSRunningApplication(processIdentifier: window.ownerPID) {
                    DebugConfig.log("WindowManager", "✅ Found Chrome app for PID \(window.ownerPID)")
                    app.activate(options: [.activateAllWindows])
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if self.focusWindowUsingAccessibility(window) {
                            DebugConfig.log("WindowManager", "✅ Successfully focused window")
                            continuation.resume()
                        } else {
                            DebugConfig.log("WindowManager", "❌ Failed to focus window using Accessibility API")
                            continuation.resume(throwing: NSError(domain: "WindowManagerError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to focus window using Accessibility API"]))
                        }
                    }
                } else {
                    DebugConfig.log("WindowManager", "❌ Failed to find Chrome application for PID \(window.ownerPID)")
                    continuation.resume(throwing: NSError(domain: "WindowManagerError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to find Chrome application"]))
                }
            }
        }
    }
    
    private func focusWindowUsingAccessibility(_ window: ChromeWindow) -> Bool {
        guard let axWindow = window.axWindow else {
            DebugConfig.log("WindowManager", "❌ Window has no AXUIElement reference")
            return false
        }
        
        DebugConfig.log("WindowManager", "🔍 Focusing window: '\(window.title)'")
        
        // If window is minimized, unminimize it first
        if window.isMinimized {
            DebugConfig.log("WindowManager", "🔄 Window is minimized, unminimizing...")
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            // Give it a moment to unminimize
            Thread.sleep(forTimeInterval: 0.2)
        }
        
        // Set window as main (focused)
        DebugConfig.log("WindowManager", "✅ Setting window as main...")
        let focusResult = AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        
        if focusResult == .success {
            DebugConfig.log("WindowManager", "✅ Successfully focused window")
            
            // Also raise the window to ensure it's visible
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            
            return true
        } else {
            DebugConfig.log("WindowManager", "❌ Failed to focus window: \(focusResult.rawValue)")
            return false
        }
    }
}

struct ChromeWindow {
    let id: CGWindowID
    let title: String
    let ownerPID: pid_t
    let bounds: [String: Any]
    let isMinimized: Bool
    let axWindow: AXUIElement?
    
    var rect: CGRect {
        guard let x = bounds["X"] as? CGFloat,
              let y = bounds["Y"] as? CGFloat,
              let width = bounds["Width"] as? CGFloat,
              let height = bounds["Height"] as? CGFloat else {
            return CGRect.zero
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}