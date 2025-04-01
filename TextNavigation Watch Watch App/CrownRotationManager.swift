import SwiftUI
import WatchConnectivity

class CrownRotationManager: NSObject, ObservableObject {
    @Published var rotationValue: Double = 0.0
    
    private var session: WCSession?
    
    override init() {
        super.init()
        print("CrownRotationManager initialized")
        setupWatchConnectivity()
    }
    
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
            print("WCSession activation requested")
        }
    }
    
    func sendCrownData(delta: Double) {
        guard let session = session, session.isReachable else {
            return
        }
        
        let message = ["crownDelta": delta]
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending crown data: \(error.localizedDescription)")
        }
        
        print("Sent crown delta: \(delta)")
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
