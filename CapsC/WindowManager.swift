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
        
        return chromeWindows
    }
    
    func activateAndCycleChrome() async throws {
        activateChrome()
        try await cycleChromeTabs()
    }
    
    private func activateChrome() {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        
        for app in runningApps {
            if app.bundleIdentifier == "com.google.Chrome" {
                app.activate(options: [.activateAllWindows])
                break
            }
        }
    }
    
    private func cycleChromeTabs() async throws {
        let chromeWindows = getChromeWindows()
        
        guard !chromeWindows.isEmpty else {
            throw NSError(domain: "WindowManagerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Chrome windows found"])
        }
        
        let frontmostWindow = getFrontmostChromeWindow(from: chromeWindows)
        let nextWindow = getNextChromeWindow(from: chromeWindows, after: frontmostWindow)
        
        try await bringWindowToFront(nextWindow)
    }
    
    private func getFrontmostChromeWindow(from windows: [ChromeWindow]) -> ChromeWindow? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return windows.first
        }
        
        for windowInfo in windowList {
            guard let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  ownerName == "Google Chrome",
                  let windowLayer = windowInfo[kCGWindowLayer as String] as? Int,
                  windowLayer == 0,
                  let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            
            if let matchingWindow = windows.first(where: { $0.id == windowID }) {
                return matchingWindow
            }
        }
        
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
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                do {
                    if let app = NSRunningApplication(processIdentifier: window.ownerPID) {
                        app.activate(options: [.activateAllWindows])
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if self.focusWindowUsingAccessibility(window) {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: NSError(domain: "WindowManagerError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to focus window using Accessibility API"]))
                            }
                        }
                    } else {
                        continuation.resume(throwing: NSError(domain: "WindowManagerError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to find Chrome application"]))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func focusWindowUsingAccessibility(_ window: ChromeWindow) -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }
        
        let app = AXUIElementCreateApplication(window.ownerPID)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return false
        }
        
        for axWindow in windows {
            var positionRef: CFTypeRef?
            let posResult = AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef)
            
            if posResult == .success,
               let positionValue = positionRef,
               CFGetTypeID(positionValue) == AXValueGetTypeID() {
                
                var cgPoint = CGPoint.zero
                if AXValueGetValue(positionValue as! AXValue, .cgPoint, &cgPoint) {
                    let windowRect = window.rect
                    
                    if abs(cgPoint.x - windowRect.origin.x) < 1.0 && abs(cgPoint.y - windowRect.origin.y) < 1.0 {
                        let focusResult = AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                        return focusResult == .success
                    }
                }
            }
        }
        
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