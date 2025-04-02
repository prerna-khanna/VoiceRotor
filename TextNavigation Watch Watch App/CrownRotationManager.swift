import SwiftUI
import WatchConnectivity

class CrownRotationManager: NSObject, ObservableObject {
    @Published var rotationValue: Double = 0.0
    private var lastSentValue: Double = 0.0
    private var session: WCSession?
    
    // Sensitivity controls with smoother values
    private let movementThreshold: Double = 0.1  // Reduced from 1.0 for more natural feel
    private let dampingFactor: Double = 0.5     // Added damping factor to smooth movement
    
    // Add a moving average filter to smooth crown movements
    private var recentDeltas: [Double] = []
    private let maxRecentDeltas = 3  // Number of values to average
    
    // Rate limiting
    private var lastMessageTime: Date = Date()
    private let minimumMessageInterval: TimeInterval = 0.2  // Slightly longer interval (5 per second)
    
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
        
        // Add to recent deltas and maintain max size
        recentDeltas.append(delta)
        if recentDeltas.count > maxRecentDeltas {
            recentDeltas.removeFirst()
        }
        
        // Calculate average delta for smoother motion
        let averageDelta = recentDeltas.reduce(0.0, +) / Double(recentDeltas.count)
        
        // Apply damping factor to smooth movements
        let smoothedDelta = averageDelta * dampingFactor
        
        // Only send if the smoothed delta is significant
        if abs(smoothedDelta) > movementThreshold {
            // Check rate limiting
            let currentTime = Date()
            if currentTime.timeIntervalSince(lastMessageTime) >= minimumMessageInterval {
                // Normalize delta to prevent extreme values - made more moderate
                let normalizedDelta = min(max(smoothedDelta, -0.5), 0.5)
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
