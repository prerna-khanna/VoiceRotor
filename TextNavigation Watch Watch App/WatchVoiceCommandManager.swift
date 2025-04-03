import SwiftUI
import WatchConnectivity
import WatchKit

class WatchVoiceCommandManager: NSObject, ObservableObject {
    @Published var recognitionStatus: String = "Ready"
    
    private var session: WCSession?
    
    override init() {
        super.init()
        setupWatchConnectivity()
    }
    
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    // Simple start voice recognition method
    func startVoiceRecognition() {
        guard let session = session, session.isReachable else {
            self.recognitionStatus = "iPhone not reachable"
            return
        }
        
        recognitionStatus = "Listening..."
        
        // Strong haptic feedback to confirm start
        WKInterfaceDevice.current().play(.notification)
        
        // Simple message to iPhone
        let message: [String: Any] = [
            "voiceCommand": "startListening"
        ]
        
        print("Watch: Starting voice recognition")
        session.sendMessage(message, replyHandler: nil) { error in
            print("Watch: Error sending start command: \(error.localizedDescription)")
            self.recognitionStatus = "Failed to start"
        }
    }
    
    // Simple stop voice recognition method
    func stopVoiceRecognition() {
        guard let session = session, session.isReachable else {
            self.recognitionStatus = "iPhone not reachable"
            return
        }
        
        // Haptic feedback to confirm stop
        WKInterfaceDevice.current().play(.success)
        
        // Simple message to iPhone
        let message: [String: Any] = [
            "voiceCommand": "stopListening"
        ]
        
        print("Watch: Stopping voice recognition")
        session.sendMessage(message, replyHandler: nil) { error in
            print("Watch: Error sending stop command: \(error.localizedDescription)")
            self.recognitionStatus = "Failed to stop"
        }
        
        // Reset status after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.recognitionStatus = "Ready"
        }
    }
}

// MARK: - WCSessionDelegate
extension WatchVoiceCommandManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("Watch: Session activation failed: \(error.localizedDescription)")
        } else {
            print("Watch: Session activated: \(activationState.rawValue)")
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // Process updates from iPhone
        DispatchQueue.main.async {
            if let status = message["voiceStatus"] as? String {
                switch status {
                case "recognized":
                    if let text = message["recognizedText"] as? String {
                        self.recognitionStatus = "Recognized: \(text)"
                    }
                case "listening":
                    self.recognitionStatus = "Listening..."
                case "error":
                    self.recognitionStatus = "Error: \(message["errorMessage"] as? String ?? "Unknown")"
                default:
                    break
                }
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("Watch: Session reachability changed: \(session.isReachable)")
    }
}
