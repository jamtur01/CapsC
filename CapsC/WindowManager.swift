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
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            print("🔍 Failed to get window list")
            return []
        }
        
        var chromeWindows: [ChromeWindow] = []
        
        for windowInfo in windowList {
            guard let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  ownerName == "Google Chrome",
                  let windowLayer = windowInfo[kCGWindowLayer as String] as? Int,
                  windowLayer == 0,
                  let windowBounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            
            let windowTitle = windowInfo[kCGWindowName as String] as? String ?? "Untitled"
            let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t ?? 0
            
            let window = ChromeWindow(
                id: windowID,
                title: windowTitle,
                ownerPID: ownerPID,
                bounds: windowBounds
            )
            
            chromeWindows.append(window)
        }
        
        print("🔍 Found \(chromeWindows.count) Chrome windows")
        for (index, window) in chromeWindows.enumerated() {
            print("  Window \(index): '\(window.title)' (ID: \(window.id))")
        }
        
        return chromeWindows
    }
    
    func activateAndCycleChrome() async throws {
        print("🔄 Starting Chrome activation and cycling...")
        activateChrome()
        try await cycleChromeTabs()
    }
    
    private func activateChrome() {
        print("🚀 Activating Chrome...")
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        
        for app in runningApps {
            if app.bundleIdentifier == "com.google.Chrome" {
                print("✅ Found Chrome app, activating...")
                app.activate(options: [.activateAllWindows])
                break
            }
        }
    }
    
    private func cycleChromeTabs() async throws {
        print("🔄 Starting tab cycling...")
        let chromeWindows = getChromeWindows()
        
        guard !chromeWindows.isEmpty else {
            print("❌ No Chrome windows found!")
            throw NSError(domain: "WindowManagerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Chrome windows found"])
        }
        
        let frontmostWindow = getFrontmostChromeWindow(from: chromeWindows)
        if let frontmost = frontmostWindow {
            print("👁️ Current frontmost window: '\(frontmost.title)' (ID: \(frontmost.id))")
        } else {
            print("⚠️ Could not determine frontmost window")
        }
        
        let nextWindow = getNextChromeWindow(from: chromeWindows, after: frontmostWindow)
        print("➡️ Next window to focus: '\(nextWindow.title)' (ID: \(nextWindow.id))")
        
        try await bringWindowToFront(nextWindow)
    }
    
    private func getFrontmostChromeWindow(from windows: [ChromeWindow]) -> ChromeWindow? {
        print("🔍 Looking for frontmost Chrome window...")
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            print("⚠️ Failed to get window list for frontmost check")
            return windows.first
        }
        
        // Window list is ordered from front to back
        for windowInfo in windowList {
            guard let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  ownerName == "Google Chrome",
                  let windowLayer = windowInfo[kCGWindowLayer as String] as? Int,
                  windowLayer == 0,
                  let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            
            if let matchingWindow = windows.first(where: { $0.id == windowID }) {
                print("✅ Found frontmost window: '\(matchingWindow.title)'")
                return matchingWindow
            }
        }
        
        print("⚠️ Could not find frontmost window in our list, returning first")
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
        print("🎯 Attempting to bring window '\(window.title)' to front...")
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                do {
                    if let app = NSRunningApplication(processIdentifier: window.ownerPID) {
                        print("✅ Found Chrome app for PID \(window.ownerPID)")
                        app.activate(options: [.activateAllWindows])
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if self.focusWindowUsingAccessibility(window) {
                                print("✅ Successfully focused window")
                                continuation.resume()
                            } else {
                                print("❌ Failed to focus window using Accessibility API")
                                continuation.resume(throwing: NSError(domain: "WindowManagerError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to focus window using Accessibility API"]))
                            }
                        }
                    } else {
                        print("❌ Failed to find Chrome application for PID \(window.ownerPID)")
                        continuation.resume(throwing: NSError(domain: "WindowManagerError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to find Chrome application"]))
                    }
                } catch {
                    print("❌ Error in bringWindowToFront: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func focusWindowUsingAccessibility(_ window: ChromeWindow) -> Bool {
        guard AXIsProcessTrusted() else {
            print("❌ Process not trusted for accessibility")
            return false
        }
        
        let app = AXUIElementCreateApplication(window.ownerPID)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            print("❌ Failed to get window list from accessibility API")
            return false
        }
        
        print("🔍 Checking \(windows.count) windows from accessibility API...")
        
        // Try a different approach: cycle through windows by index
        // The window order in the accessibility API should match the window order from CGWindowList
        let chromeWindows = getChromeWindows()
        if let targetIndex = chromeWindows.firstIndex(where: { $0.id == window.id }) {
            print("🎯 Target window is at index \(targetIndex) in our list")
            
            // If we have the same number of windows, use the index directly
            if windows.count == chromeWindows.count && targetIndex < windows.count {
                let axWindow = windows[targetIndex]
                print("✅ Using index-based matching, setting window at index \(targetIndex) as main...")
                let focusResult = AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                if focusResult == .success {
                    print("✅ Successfully set window as main")
                    return true
                } else {
                    print("❌ Failed to set window as main: \(focusResult.rawValue)")
                }
            }
        }
        
        // Fallback: try to match by title
        for (index, axWindow) in windows.enumerated() {
            var titleRef: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            
            if titleResult == .success,
               let axTitle = titleRef as? String {
                print("  Window \(index) title: '\(axTitle)'")
                
                if axTitle == window.title {
                    print("✅ Found matching window by title, setting as main...")
                    let focusResult = AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                    if focusResult == .success {
                        print("✅ Successfully set window as main")
                        return true
                    } else {
                        print("❌ Failed to set window as main: \(focusResult.rawValue)")
                    }
                }
            }
        }
        
        // Last resort: Just cycle to the next window in the list
        if windows.count > 1 {
            print("⚠️ Could not match specific window, cycling to next in list...")
            // Find the current main window
            var currentMainIndex = 0
            for (index, axWindow) in windows.enumerated() {
                var isMainRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, kAXMainAttribute as CFString, &isMainRef) == .success,
                   let isMain = isMainRef as? Bool, isMain {
                    currentMainIndex = index
                    print("  Current main window is at index \(index)")
                    break
                }
            }
            
            let nextIndex = (currentMainIndex + 1) % windows.count
            let nextWindow = windows[nextIndex]
            print("  Setting window at index \(nextIndex) as main...")
            let focusResult = AXUIElementSetAttributeValue(nextWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            if focusResult == .success {
                print("✅ Successfully cycled to next window")
                return true
            } else {
                print("❌ Failed to cycle: \(focusResult.rawValue)")
            }
        }
        
        print("❌ No matching window found in accessibility API")
        return false
    }
}

struct ChromeWindow {
    let id: CGWindowID
    let title: String
    let ownerPID: pid_t
    let bounds: [String: Any]
    
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