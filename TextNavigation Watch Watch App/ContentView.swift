import SwiftUI
import WatchConnectivity
import WatchKit
import AVFoundation

struct WatchAppView: View {
    @StateObject private var crownManager = CrownRotationManager()
    @StateObject private var motionManager = MotionManager()
    @StateObject private var voiceManager = WatchVoiceCommandManager()
    @State private var crownValue: Double = 0.0
    @State private var isActive: Bool = false
    @State private var isMotionActive: Bool = false
    @State private var isListeningForVoice: Bool = false
    @State private var lastMovementDirection: String = "None"
    @State private var lastCrownValue: Double = 0.0
    
    // Timer for detecting crown press simulation
    @State private var crownPressTimer: Timer? = nil
    
    var body: some View {
        VStack(spacing: 8) {
            if isActive {
                Text("Navigation Active")
                    .font(.headline)
                
                Text("Crown: \(crownValue, specifier: "%.1f")")
                    .font(.body)
                
                Text("Last Move: \(lastMovementDirection)")
                    .font(.caption)
                    .foregroundColor(.green)
                
                if isListeningForVoice {
                    Text("Listening...")
                        .font(.headline)
                        .foregroundColor(.red)
                }
                
                if isMotionActive {
                    Group {
                        Text("X: \(motionManager.rotationRateX, specifier: "%.1f")")
                        Text("Y: \(motionManager.rotationRateY, specifier: "%.1f")")
                        Text("Z: \(motionManager.rotationRateZ, specifier: "%.1f")")
                    }
                    .font(.caption)
                    
                    Text("Motion: \(motionManager.timeRemaining)s")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if motionManager.isSendingData {
                    Text("Motion ending...")
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Text("Motion tracking complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Instruction text that's accessible to VoiceOver
                Text("Long press anywhere for voice")
                    .font(.caption)
                    .foregroundColor(isListeningForVoice ? .red : .gray)
                    .accessibilityLabel("Long press anywhere on screen to activate voice commands")
            } else {
                Text("Tap to Start")
                    .font(.headline)
            }
        }
        .padding()
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: -5.0,
            through: 5.0,
            by: 0.1,
            sensitivity: .low,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { newValue in
            if isActive {
                // Update direction indicator for visual feedback
                if newValue > crownManager.rotationValue {
                    lastMovementDirection = "Forward →"
                } else if newValue < crownManager.rotationValue {
                    lastMovementDirection = "← Backward"
                }
                
                // Update the crown manager
                crownManager.updateRotation(newValue: newValue)
                
                // Check for crown press simulation (if crown is held still for a moment)
                checkForCrownPress(newValue)
                
                // Add haptic feedback - use lighter feedback for smoother feel
                WKInterfaceDevice.current().play(.click)
            }
        }
        .onAppear {
            print("WatchAppView appeared")
            motionManager.startUpdates()
            
            // Register for notifications about side button press
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("SideButtonPressed"),
                object: nil,
                queue: .main) { _ in
                    self.handleSideButtonPress()
                }
            
            // Enable button event handling in the app
            enableButtonPressDetection()
        }
        .onDisappear {
            print("WatchAppView disappeared")
            motionManager.stopUpdates()
            motionManager.stopSendingData()
            
            // Stop any active crown press detection
            crownPressTimer?.invalidate()
            crownPressTimer = nil
            
            // Remove notification observer
            NotificationCenter.default.removeObserver(self)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // If not active yet, start everything
            if !isActive {
                isActive = true
                isMotionActive = true
                print("Crown navigation and motion tracking activated")
                crownValue = 0.0
                lastMovementDirection = "None"
                motionManager.startSendingData()
                
                // After 5 seconds, automatically deactivate only motion tracking
                DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) {
                    if isMotionActive {
                        isMotionActive = false
                        motionManager.stopSendingData()
                        print("Motion tracking automatically deactivated after 20 seconds")
                    }
                }
            }
            // If already active but motion tracking is inactive, restart motion tracking
            else if isActive && !isMotionActive && !motionManager.isSendingData {
                isMotionActive = true
                print("Restarting motion tracking")
                motionManager.startSendingData()
                
                // Set timer to stop after 20 seconds again
                DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) {
                    if isMotionActive {
                        isMotionActive = false
                        motionManager.stopSendingData()
                        print("Motion tracking automatically deactivated after 20 seconds")
                    }
                }
                
                // Provide haptic feedback to confirm restart
                WKInterfaceDevice.current().play(.success)
            }
        }
        // Add a simple onLongPressGesture that triggers only after the app is active
        .onLongPressGesture(minimumDuration: 1.0) {
            if isActive {
                print("DEBUG: Long press detected on watch")
                startVoiceRecognition()
            }
        }
    }
    
    private func enableButtonPressDetection() {
        print("DEBUG: Setting up long press detection as primary voice activation method")
    }
    
    private func checkForCrownPress(_ newValue: Double) {
        // We're not using crown movement patterns for activation anymore
        // Just update last value for crown rotation tracking
        lastCrownValue = newValue
    }
    
    private func handleSideButtonPress() {
        guard isActive else { return }
        
        print("DEBUG: Side button pressed!")
        
        // Toggle voice listening state
        startVoiceRecognition()
    }
    
    private func startVoiceRecognition() {
        // Don't start if already listening
        if isListeningForVoice {
            return
        }
        
        isListeningForVoice = true
            
        // Start listening for voice commands
        print("DEBUG: Starting voice command listening")
        WKInterfaceDevice.current().play(.start)
        
        // Send message to phone to start voice recognition
        voiceManager.startVoiceRecognition()
        
        // Auto-stop after 10 seconds (safety timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.isListeningForVoice {
                self.stopVoiceRecognition()
            }
        }
    }
    
    private func stopVoiceRecognition() {
        isListeningForVoice = false
        print("DEBUG: Stopping voice command listening")
        WKInterfaceDevice.current().play(.stop)
        voiceManager.stopVoiceRecognition()
    }
}
