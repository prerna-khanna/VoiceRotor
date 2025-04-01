//
//  WatchCrownNavigator.swift
//  TextNavigation
//
//  Created by Prerna Khanna on 3/27/25.
//

import Foundation
import WatchConnectivity

enum NavigationDirection {
    case forward
    case backward
}

protocol WatchCrownNavigatorDelegate: AnyObject {
    func didNavigate(direction: NavigationDirection, magnitude: Double)
    func didDetectPauseAtPosition()
}

class WatchCrownNavigator: NSObject, WCSessionDelegate {
    // MARK: - Properties
    weak var delegate: WatchCrownNavigatorDelegate?
    
    private var wcSession: WCSession?
    private var lastCrownPosition: Double = 0.0
    private var lastUpdateTime: Date = Date()
    private var pauseTimer: Timer?
    private let pauseThreshold: TimeInterval = 0.5  // Time in seconds to detect a pause
    private let movementThreshold: Double = 0.05    // Minimum movement to register navigation
    private var errorProbabilities: [NSRange: Double] = [:]  // Store error probabilities
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupWatchConnectivity()
    }
    
    // MARK: - Public Methods
    
    /// Update error probabilities for current text
    /// - Parameter probabilities: Dictionary mapping ranges to error probabilities
    func updateErrorProbabilities(_ probabilities: [NSRange: Double]) {
        self.errorProbabilities = probabilities
    }
    
    // MARK: - Private Methods
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            wcSession = WCSession.default
            wcSession?.delegate = self
            wcSession?.activate()
        }
    }
    
    private func processRotationData(crownDelta: Double) {
        // Determine direction and magnitude
        let direction: NavigationDirection = crownDelta > 0 ? .forward : .backward
        
        // Use absolute value for magnitude
        let magnitude = min(1.0, abs(crownDelta))
        
        // Only process if the movement exceeds the threshold
        if magnitude > movementThreshold {
            // Reset the pause timer if we're moving
            pauseTimer?.invalidate()
            
            // Notify the delegate
            delegate?.didNavigate(direction: direction, magnitude: magnitude)
            
            // Start a new pause timer
            pauseTimer = Timer.scheduledTimer(withTimeInterval: pauseThreshold, repeats: false) { [weak self] _ in
                self?.delegate?.didDetectPauseAtPosition()
            }
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
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive.")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession deactivated.")
        wcSession?.activate()
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // Process crown rotation data
        if let crownDelta = message["crownDelta"] as? Double {
            print("Received crown rotation: \(crownDelta)")
            
            DispatchQueue.main.async { [weak self] in
                self?.processRotationData(crownDelta: crownDelta)
            }
        }
    }
}
