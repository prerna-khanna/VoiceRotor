import SwiftUI
import CoreMotion
import WatchConnectivity

class MotionManager: NSObject, ObservableObject {
    private var motionManager = CMMotionManager()
    private var session: WCSession?
    
    @Published var rotationRateX: Double = 0.0
    @Published var rotationRateY: Double = 0.0
    @Published var rotationRateZ: Double = 0.0
    @Published var isSendingData: Bool = false
    
    override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    func startUpdates() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1
            motionManager.startDeviceMotionUpdates(to: OperationQueue.main) { [weak self] (data, error) in
                guard let self = self, let data = data else { return }
                
                self.rotationRateX = data.rotationRate.x
                self.rotationRateY = data.rotationRate.y
                self.rotationRateZ = data.rotationRate.z
                
                if self.isSendingData {
                    self.sendMotionData()
                }
            }
        }
    }
    
    func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
    
    func startSendingData() {
        isSendingData = true
    }
    
    func stopSendingData() {
        isSendingData = false
    }
    
    private func sendMotionData() {
        guard let session = session, session.isReachable else { return }
        
        let message: [String: Any] = [
            "rotationRateX": rotationRateX,
            "rotationRateY": rotationRateY,
            "rotationRateZ": rotationRateZ
        ]
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending motion data: \(error)")
        }
    }
}

extension MotionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Just implementation to satisfy protocol
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        // Just implementation to satisfy protocol
    }
}
