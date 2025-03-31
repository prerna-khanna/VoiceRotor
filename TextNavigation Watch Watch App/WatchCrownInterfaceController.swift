//
//  WatchCrownInterfaceController.swift
//  TextNavigation
//
//  Created by Prerna Khanna on 3/27/25.
//

import WatchKit
import Foundation
import WatchConnectivity
import CoreMotion

class WatchCrownInterfaceController: WKInterfaceController, WCSessionDelegate {
    // MARK: - Interface Elements
    @IBOutlet weak var statusLabel: WKInterfaceLabel!
    @IBOutlet weak var crownValueLabel: WKInterfaceLabel!
    
    // MARK: - Properties
    private var wcSession: WCSession?
    private var lastCrownValue: Double = 0.0
    private var isSendingData = false
    private var motionManager = CMMotionManager()
    private var crownAccumulator: Double = 0.0
    private var sendingTimer: Timer?
    
    // MARK: - Lifecycle Methods
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        setupWatchConnectivity()
        updateInterface()
        
        // Enable crown rotation events
        crownSequencer.delegate = self
        crownSequencer.focus()
    }
    
    override func willActivate() {
        super.willActivate()
        crownSequencer.focus()
        setupGyroDataCollection()
    }
    
    override func didDeactivate() {
        super.didDeactivate()
        stopSendingData()
        motionManager.stopGyroUpdates()
    }
    
    // MARK: - Interface Actions
    @IBAction func toggleSendingData() {
        isSendingData = !isSendingData
        updateInterface()
        
        if isSendingData {
            startSendingData()
        } else {
            stopSendingData()
        }
    }
    
    // MARK: - Private Methods
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            wcSession = WCSession.default
            wcSession?.delegate = self
            wcSession?.activate()
        }
    }
    
    private func updateInterface() {
        statusLabel.setText(isSendingData ? "Sending Data" : "Ready")
    }
    
    private func startSendingData() {
        // Create a timer to send accumulated crown rotation data
        sendingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.sendCrownRotationData()
        }
    }
    
    private func stopSendingData() {
        sendingTimer?.invalidate()
        sendingTimer = nil
    }
    
    private func sendCrownRotationData() {
        // Only send if there's movement (accumulated delta)
        if abs(crownAccumulator) > 0.001 {
            guard let session = wcSession, session.isReachable else {
                print("WCSession is not reachable.")
                return
            }
            
            let data: [String: Any] = [
                "crownDelta": crownAccumulator
            ]
            
            session.sendMessage(data, replyHandler: nil) { error in
                print("Failed to send crown data: \(error.localizedDescription)")
            }
            
            // Update the interface
            crownValueLabel.setText(String(format: "Δ: %.2f", crownAccumulator))
            
            // Reset the accumulator after sending
            crownAccumulator = 0.0
        }
    }
    
    private func setupGyroDataCollection() {
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 0.1
            motionManager.startGyroUpdates(to: OperationQueue.main) { [weak self] (gyroData, error) in
                guard let self = self, let gyroData = gyroData else {
                    if let error = error {
                        print("Gyro update error: \(error.localizedDescription)")
                    }
                    return
                }
                
                // Process gyro data (for gesture recognition)
                if self.isSendingData {
                    self.sendGyroData(gyroData)
                }
            }
        }
    }
    
    private func sendGyroData(_ gyroData: CMGyroData) {
        guard let session = wcSession, session.isReachable else {
            print("WCSession is not reachable.")
            return
        }
        
        let data: [String: Any] = [
            "rotationRateX": gyroData.rotationRate.x,
            "rotationRateY": gyroData.rotationRate.y,
            "rotationRateZ": gyroData.rotationRate.z
        ]
        
        session.sendMessage(data, replyHandler: nil) { error in
            print("Failed to send gyro data: \(error.localizedDescription)")
        }
    }
    
    // MARK: - WCSessionDelegate Methods
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed with error: \(error.localizedDescription)")
        } else {
            print("WCSession activated with state: \(activationState.rawValue)")
        }
    }
}

// MARK: - WKCrownDelegate
extension WatchCrownInterfaceController: WKCrownDelegate {
    func crownDidRotate(_ crownSequencer: WKCrownSequencer?, rotationalDelta: Double) {
        // Accumulate the rotation delta
        crownAccumulator += rotationalDelta
        
        // Update the interface immediately for responsiveness
        crownValueLabel.setText(String(format: "Δ: %.2f", crownAccumulator))
    }
    
    func crownDidBecomeIdle(_ crownSequencer: WKCrownSequencer?) {
        // Handle idle state if needed
        print("Crown became idle")
    }
}
