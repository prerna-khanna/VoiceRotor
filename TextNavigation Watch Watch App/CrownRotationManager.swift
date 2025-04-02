import SwiftUI
import WatchConnectivity

class CrownRotationManager: NSObject, ObservableObject {
    @Published var rotationValue: Double = 0.0
    private var lastSentValue: Double = 0.0
    private var session: WCSession?
    
    // Sensitivity control
    private let movementThreshold: Double = 0.2  // Increased from 0.05 to 0.2
    
    // Rate limiting
    private var lastMessageTime: Date = Date()
    private let minimumMessageInterval: TimeInterval = 0.25  // At most 4 messages per second
    
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
    
    func updateRotation(newValue: Double) {
        rotationValue = newValue
        
        // Calculate the delta (change) since the last sent value
        let delta = newValue - lastSentValue
        
        // Only send if the delta is significant (avoid micro-movements)
        if abs(delta) > movementThreshold {
            // Check rate limiting
            let currentTime = Date()
            if currentTime.timeIntervalSince(lastMessageTime) >= minimumMessageInterval {
                // Normalize delta to prevent extreme values
                let normalizedDelta = min(max(delta, -1.0), 1.0)
                sendCrownData(delta: normalizedDelta)
                lastSentValue = newValue
                lastMessageTime = currentTime
            }
        }
    }
    
    func sendCrownData(delta: Double) {
        guard let session = session, session.isReachable else {
            print("Watch session not reachable")
            return
        }
        
        // Round delta to reduce noise
        let roundedDelta = round(delta * 100) / 100
        
        let message: [String: Any] = [
            "crownDelta": roundedDelta
        ]
        
        print("Sending crown delta: \(roundedDelta)")
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending crown data: \(error.localizedDescription)")
        }
    }
}

extension CrownRotationManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed: \(error.localizedDescription)")
        } else {
            print("WCSession activated with state: \(activationState.rawValue)")
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("WCSession reachability changed: \(session.isReachable)")
    }
}
