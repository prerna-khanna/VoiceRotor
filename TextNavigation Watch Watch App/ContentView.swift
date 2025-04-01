import SwiftUI
import WatchConnectivity
import WatchKit


struct WatchAppView: View {
    @StateObject private var crownManager = CrownRotationManager()
    @StateObject private var motionManager = MotionManager()
    @State private var crownValue: Double = 0.0
    @State private var isActive: Bool = false
    
    var body: some View {
        VStack(spacing: 8) {
            if isActive {
                Text("Navigation Active")
                    .font(.headline)
                
                Text("Crown: \(crownValue, specifier: "%.2f")")
                    .font(.body)
                
                Group {
                    Text("X: \(motionManager.rotationRateX, specifier: "%.2f")")
                    Text("Y: \(motionManager.rotationRateY, specifier: "%.2f")")
                    Text("Z: \(motionManager.rotationRateZ, specifier: "%.2f")")
                }
                .font(.caption)
            } else {
                Text("Tap to Start")
                    .font(.headline)
            }
        }
        .padding()
        .focusable() // Make the view focusable to receive digital crown events
        .digitalCrownRotation($crownValue,from: 0, through: 100, by: 1, intent: .adjusting)
        { event in
            if isActive && event.offset != 0 {
                crownManager.sendCrownData(delta: event.offset)
            }
        }        .onAppear {
            print("WatchAppView appeared")
            motionManager.startUpdates()
        }
        .onDisappear {
            print("WatchAppView disappeared")
            motionManager.stopUpdates()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isActive.toggle()
            print("Crown navigation \(isActive ? "activated" : "deactivated")")
            if isActive {
                motionManager.startSendingData()
            } else {
                motionManager.stopSendingData()
            }
        }
    }
}
