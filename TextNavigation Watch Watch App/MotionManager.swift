import SwiftUI
import CoreMotion
import WatchConnectivity
import WatchKit

class MotionManager: NSObject, ObservableObject {
    private var motionManager = CMMotionManager()
    private var session: WCSession?
    private var streamTimer: Timer?
    private var keepAwakeTimer: Timer?
    private let streamDuration: TimeInterval = 20.0
    
    @Published var rotationRateX: Double = 0.0
    @Published var rotationRateY: Double = 0.0
    @Published var rotationRateZ: Double = 0.0
    @Published var isSendingData: Bool = false
    @Published var timeRemaining: Int = 20
    @Published var displayKeepAliveCounter: Int = 0  // This forces UI updates
    
    override init() {
        super.init()
        setupSession()
    }
    
    deinit {
        stopKeepingDisplayAwake()
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
        timeRemaining = 20
        
        // Play haptic feedback when starting data collection
        WKInterfaceDevice.current().play(.success)
        
        // Keep the display awake by forcing UI updates
        startKeepingDisplayAwake()
        
        // Start timer to stop sending after 20 seconds
        streamTimer?.invalidate()
        streamTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            self.timeRemaining -= 1
            
            if self.timeRemaining <= 0 {
                self.stopSendingData()
                timer.invalidate()
            }
        }
        
        // Send a notification to the phone that motion data collection has started
        sendStatusUpdate(started: true)
    }
    
    func stopSendingData() {
        isSendingData = false
        streamTimer?.invalidate()
        streamTimer = nil
        
        // Stop keeping display awake
        stopKeepingDisplayAwake()
        
        // Play a distinct haptic when streaming stops automatically
        WKInterfaceDevice.current().play(.notification)
        
        // Send a notification to the phone that motion data collection has stopped
        sendStatusUpdate(started: false)
    }
    
    // Method to keep display awake via frequent UI updates
    private func startKeepingDisplayAwake() {
        keepAwakeTimer?.invalidate()
        keepAwakeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            // Update a published property to force UI refresh
            guard let self = self else { return }
            self.displayKeepAliveCounter += 1
            
            // Force haptic feedback occasionally to maintain user attention
            if self.displayKeepAliveCounter % 10 == 0 {
                // Very light tap every 5 seconds
                WKInterfaceDevice.current().play(.click)
            }
            
            print("Keeping display active via UI updates...")
        }
    }
    
    private func stopKeepingDisplayAwake() {
        keepAwakeTimer?.invalidate()
        keepAwakeTimer = nil
        print("Stopped keeping display active")
    }
    
    private func sendStatusUpdate(started: Bool) {
        guard let session = session, session.isReachable else { return }
        
        let message: [String: Any] = [
            "motionStatus": started ? "started" : "stopped"
        ]
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending motion status update: \(error)")
        }
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
