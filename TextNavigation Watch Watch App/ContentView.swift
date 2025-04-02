import SwiftUI
import WatchConnectivity
import WatchKit

struct WatchAppView: View {
    @StateObject private var crownManager = CrownRotationManager()
    @StateObject private var motionManager = MotionManager()
    @State private var crownValue: Double = 0.0
    @State private var isActive: Bool = false
    @State private var isMotionActive: Bool = false // New state to track motion separately
    @State private var lastMovementDirection: String = "None"
    
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
            by: 0.1, // More fine-grained control with smaller steps
            sensitivity: .low, // Lower sensitivity for smoother experience
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
                
                // Add haptic feedback - use lighter feedback for smoother feel
                WKInterfaceDevice.current().play(.click)
            }
        }
        .onAppear {
            print("WatchAppView appeared")
            motionManager.startUpdates()
        }
        .onDisappear {
            print("WatchAppView disappeared")
            motionManager.stopUpdates()
            motionManager.stopSendingData()
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
                
                // After 20 seconds, automatically deactivate only motion tracking
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
    }
}
