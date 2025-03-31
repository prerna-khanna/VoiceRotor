//
//  TextNavigation_WatchApp.swift
//  TextNavigation Watch Watch App
//
//  Created by Prerna Khanna on 3/27/25.
//

import SwiftUI
import CoreMotion
import WatchConnectivity
import WatchKit

@main
struct TextNavigation_Watch_Watch_AppApp: App {
    @SceneBuilder var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}

struct WatchContentView: View {
    @StateObject private var motionManager = MotionManager()
    
    var body: some View {
        VStack {
            if motionManager.isSendingData {
                Text("Sending Data...")
                    .font(.headline)
                Text("Rotation X: \(motionManager.rotationRateX, specifier: "%.2f")")
                Text("Rotation Y: \(motionManager.rotationRateY, specifier: "%.2f")")
                Text("Rotation Z: \(motionManager.rotationRateZ, specifier: "%.2f")")
            } else {
                Text("Tap to Start")
                    .font(.headline)
            }
        }
        .onAppear {
            motionManager.startUpdates()
        }
        .onDisappear {
            motionManager.stopUpdates()
        }
        .contentShape(Rectangle()) // Makes the entire view tappable
        .onTapGesture {
            motionManager.startSendingDataForDuration(20) // Trigger data send for 20 seconds on tap
        }
    }
}

class MotionManager: NSObject, ObservableObject, WCSessionDelegate {
    private var motionManager: CMMotionManager
    private var wcSession: WCSession?
    private var timer: Timer?
    private var extendedRuntimeSession: WKExtendedRuntimeSession?
    
    @Published var rotationRateX: Double = 0.0
    @Published var rotationRateY: Double = 0.0
    @Published var rotationRateZ: Double = 0.0
    @Published var isSendingData: Bool = false

    override init() {
        self.motionManager = CMMotionManager()
        super.init()
        setupWatchConnectivity()
        setupExtendedRuntimeSession()
    }
    
    func startUpdates() {
        if motionManager.isDeviceMotionAvailable {
            print("Device Motion is available.")
            motionManager.deviceMotionUpdateInterval = 0.1
            motionManager.startDeviceMotionUpdates(to: OperationQueue.main) { [weak self] (motionData, error) in
                guard let self = self, let motionData = motionData else {
                    if let error = error {
                        print("Device Motion update error: \(error.localizedDescription)")
                    }
                    return
                }
                
                self.rotationRateX = motionData.rotationRate.x
                self.rotationRateY = motionData.rotationRate.y
                self.rotationRateZ = motionData.rotationRate.z
                
                // Debug statements to see the values
                print("Rotation Rate X: \(self.rotationRateX)")
                print("Rotation Rate Y: \(self.rotationRateY)")
                print("Rotation Rate Z: \(self.rotationRateZ)")
                
                // Send data only if it's within the sending period
                if self.isSendingData {
                    self.sendRotationDataToPhone()
                }
            }
        } else {
            print("Device Motion is not available.")
        }
    }
    
    func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
    
    func startSendingDataForDuration(_ duration: TimeInterval) {
        isSendingData = true
        extendedRuntimeSession?.start() // Start extended runtime session

        // Start a timer to stop sending data after the specified duration
        timer?.invalidate() // Invalidate any existing timer
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.stopSendingData()
        }
    }
    
    private func stopSendingData() {
        isSendingData = false
        timer?.invalidate()
        extendedRuntimeSession?.invalidate() // Invalidate extended runtime session
        print("Stopped sending data.")
    }
    
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            wcSession = WCSession.default
            wcSession?.delegate = self
            wcSession?.activate()
        }
    }
    
    private func sendRotationDataToPhone() {
        guard let session = wcSession, session.isReachable else {
            print("WCSession is not reachable.")
            return
        }
        
        let data = [
            "rotationRateX": rotationRateX,
            "rotationRateY": rotationRateY,
            "rotationRateZ": rotationRateZ
        ]
        
        session.sendMessage(data, replyHandler: nil) { error in
            print("Failed to send data: \(error.localizedDescription)")
        }
    }
    
    private func setupExtendedRuntimeSession() {
        extendedRuntimeSession = WKExtendedRuntimeSession()
        // Not setting the delegate, so we don't need to implement WKExtendedRuntimeSessionDelegate
    }
    
    // MARK: - WCSessionDelegate Methods
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed with error: \(error.localizedDescription)")
        } else {
            print("WCSession activated with state: \(activationState.rawValue)")
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            print("WCSession is reachable")
        } else {
            print("WCSession is not reachable")
        }
    }
}
