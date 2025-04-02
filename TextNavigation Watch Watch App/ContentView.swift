import SwiftUI
import WatchConnectivity
import WatchKit

struct WatchAppView: View {
    @StateObject private var crownManager = CrownRotationManager()
    @StateObject private var motionManager = MotionManager()
    @State private var crownValue: Double = 0.0
    @State private var isActive: Bool = false
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
                
                Group {
                    Text("X: \(motionManager.rotationRateX, specifier: "%.1f")")
                    Text("Y: \(motionManager.rotationRateY, specifier: "%.1f")")
                    Text("Z: \(motionManager.rotationRateZ, specifier: "%.1f")")
                }
                .font(.caption)
                
                if motionManager.isSendingData {
                    Text("Time remaining: \(motionManager.timeRemaining)s")
                        .font(.caption)
                        .foregroundColor(.orange)
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
            by: 0.2,
            sensitivity: .medium,
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
                
                // Add haptic feedback
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
            // Only allow tapping to start, not to stop
            if !isActive {
                isActive = true
                print("Crown navigation activated")
                crownValue = 0.0
                lastMovementDirection = "None"
                motionManager.startSendingData()
                
                // After 20 seconds, automatically deactivate
                DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) {
                    if isActive {
                        isActive = false
                        print("Crown navigation automatically deactivated after 20 seconds")
                    }
                }
            }
        }
    }
}
