import SwiftUI
import CoreMotion
import WatchConnectivity
import WatchKit

// Coordinator to handle crown rotation via WKCrownDelegate
class CrownDelegate: NSObject, WKCrownDelegate, ObservableObject {
    @Published var crownAccumulator: Double = 0.0
    var motionManager: MotionManager?
    
    func crownDidRotate(_ crownSequencer: WKCrownSequencer?, rotationalDelta: Double) {
        print("Crown rotated: \(rotationalDelta)")
        crownAccumulator += rotationalDelta
        
        if abs(crownAccumulator) > 0.05 {
            let dataToSend = crownAccumulator
            motionManager?.sendCrownRotationData(delta: dataToSend)
            crownAccumulator = 0.0
        }
    }
    
    func crownDidBecomeIdle(_ crownSequencer: WKCrownSequencer?) {
        print("Crown became idle")
    }
}

// HostingController to connect SwiftUI with WKCrownDelegate
class HostingController: WKHostingController<WatchContentView> {
    let crownDelegate = CrownDelegate()
    
    override var body: WatchContentView {
        WatchContentView(crownDelegate: crownDelegate)
    }
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        // Set up crown rotation handling
        crownSequencer.delegate = crownDelegate
        crownSequencer.focus()
        
        print("Crown delegate initialized in WKHostingController")
    }
}

// Entry point for the app
@main
struct TextNavigation_Watch_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor var appDelegate: AppDelegate
    
    var body: some Scene {
        WindowGroup {
            WatchContentView(crownDelegate: appDelegate.crownDelegate)
        }
    }
}

// App delegate to initialize crown handling
class AppDelegate: NSObject, WKApplicationDelegate {
    let crownDelegate = CrownDelegate()
    
    func applicationDidFinishLaunching() {
        print("Application did finish launching")
        // Set up crown delegate here if needed
    }
}

struct WatchContentView: View {
    @StateObject private var motionManager = MotionManager()
    @ObservedObject var crownDelegate: CrownDelegate
    
    init(crownDelegate: CrownDelegate) {
        self.crownDelegate = crownDelegate
        crownDelegate.motionManager = motionManager
    }
    
    var body: some View {
        VStack(spacing: 10) {
            if motionManager.isSendingData {
                Text("Navigation Active")
                    .font(.headline)
                
                Text("Crown: \(crownDelegate.crownAccumulator, specifier: "%.2f")")
                    .font(.body)
                
                Group {
                    Text("X: \(motionManager.rotationRateX, specifier: "%.2f")")
                    Text("Y: \(motionManager.rotationRateY, specifier: "%.2f")")
                    Text("Z: \(motionManager.rotationRateZ, specifier: "%.2f")")
                }
                .font(.caption)
                
                Text("Rotate crown to navigate")
                    .font(.caption)
            } else {
                Text("Tap to Start")
                    .font(.headline)
            }
        }
        .padding()
        .onAppear {
            print("Watch content view appeared")
            motionManager.startUpdates()
        }
        .onDisappear {
            print("Watch content view disappeared")
            motionManager.stopUpdates()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            print("Tap detected, starting data sending")
            if !motionManager.isSendingData {
                motionManager.startSendingDataForDuration(20)
            }
        }
    }
}

class MotionManager: NSObject, ObservableObject, WCSessionDelegate {
    private var motionManager: CMMotionManager
    private var wcSession: WCSession?
    private var timer: Timer?
    
    @Published var rotationRateX: Double = 0.0
    @Published var rotationRateY: Double = 0.0
    @Published var rotationRateZ: Double = 0.0
    @Published var isSendingData: Bool = false

    override init() {
        print("MotionManager initializing")
        self.motionManager = CMMotionManager()
        super.init()
        setupWatchConnectivity()
    }
    
    func startUpdates() {
        if motionManager.isDeviceMotionAvailable {
            print("Device Motion is available, starting updates")
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
                
                // Send data only if it's within the sending period
                if self.isSendingData {
                    self.sendRotationDataToPhone()
                }
            }
        } else {
            print("Device Motion is NOT available")
        }
    }
    
    func stopUpdates() {
        print("Stopping motion updates")
        motionManager.stopDeviceMotionUpdates()
    }
    
    func startSendingDataForDuration(_ duration: TimeInterval) {
        print("Starting to send data for \(duration) seconds")
        isSendingData = true

        // Start a timer to stop sending data after the specified duration
        timer?.invalidate() // Invalidate any existing timer
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            print("Timer fired, stopping data sending")
            self?.stopSendingData()
        }
    }
    
    private func stopSendingData() {
        print("Stopping data sending")
        isSendingData = false
        timer?.invalidate()
    }
    
    private func setupWatchConnectivity() {
        print("Setting up watch connectivity")
        if WCSession.isSupported() {
            wcSession = WCSession.default
            wcSession?.delegate = self
            wcSession?.activate()
            print("WCSession activation requested")
        } else {
            print("WCSession is not supported on this device")
        }
    }
    
    func sendCrownRotationData(delta: Double) {
        guard isSendingData else {
            print("Not sending crown data - sending is disabled")
            return
        }
        
        guard let session = wcSession else {
            print("Cannot send crown data - session is nil")
            return
        }
        
        guard session.isReachable else {
            print("Cannot send crown data - session is not reachable")
            return
        }
        
        let data = [
            "crownDelta": delta
        ]
        
        print("Sending crown delta: \(delta)")
        session.sendMessage(data, replyHandler: { reply in
            print("Crown data send success with reply: \(reply)")
        }) { error in
            print("Failed to send crown data: \(error.localizedDescription)")
        }
    }
    
    private func sendRotationDataToPhone() {
        guard let session = wcSession, session.isReachable else {
            return  // Silent return to reduce log spam
        }
        
        let data = [
            "rotationRateX": rotationRateX,
            "rotationRateY": rotationRateY,
            "rotationRateZ": rotationRateZ
        ]
        
        session.sendMessage(data, replyHandler: nil) { error in
            print("Failed to send rotation data: \(error.localizedDescription)")
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

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("WCSession reachability changed: \(session.isReachable ? "reachable" : "not reachable")")
    }
}
