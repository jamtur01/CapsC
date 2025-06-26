import Foundation
import Cocoa

class WindowManager {
    
    init() {}
    
    func isChromeRunning() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == "com.google.Chrome" }
    }
    
    func getChromeWindowCount() -> Int {
        let script = """
            tell application "Google Chrome"
                return count of windows
            end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let result = scriptObject.executeAndReturnError(&error)
            if error == nil {
                return result.int32Value == 0 ? 0 : Int(result.int32Value)
            }
        }
        return 0
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
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                if let scriptObject = NSAppleScript(source: script) {
                    scriptObject.executeAndReturnError(&error)
                    if let error = error {
                        continuation.resume(throwing: NSError(domain: "AppleScriptError", code: -1, userInfo: [NSLocalizedDescriptionKey: error.description]))
                    } else {
                        continuation.resume()
                    }
                } else {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create AppleScript"]))
                }
            }
        }
    }
}