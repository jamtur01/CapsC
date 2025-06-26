import Foundation
import Cocoa

class PermissionManager: ObservableObject {
    @Published var isAccessibilityGranted = false
    private var pollTimer: Timer?
    
    init() {
        checkPermissions()
        startPolling()
    }
    
    deinit {
        stopPolling()
    }
    
    func checkPermissions() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }
    
    func requestPermissions() {
        // Only show the system prompt - it has its own "Open System Preferences" button
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        
        // This shows the system accessibility prompt
        _ = AXIsProcessTrustedWithOptions(options)
        
        // Don't open System Preferences separately - the prompt handles this
        // The user can click "Open System Preferences" in the prompt if needed
    }
    
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                self.checkPermissions()
            }
        }
    }
    
    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}