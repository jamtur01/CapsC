import Foundation

/// Central debug configuration for CapsC
struct DebugConfig {
    /// Master debug flag - set to true to enable verbose logging across the app
    static let debugMode = false
    
    /// Print debug message if debug mode is enabled
    static func log(_ message: String) {
        if debugMode {
            print(message)
        }
    }
    
    /// Print debug message with a specific category prefix
    static func log(_ category: String, _ message: String) {
        if debugMode {
            print("[\(category)] \(message)")
        }
    }
}