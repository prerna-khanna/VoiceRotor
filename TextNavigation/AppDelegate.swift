import UIKit
import WatchConnectivity

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, WCSessionDelegate {

    var window: UIWindow?

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
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        NotificationCenter.default.post(name: .didReceiveRotationData, object: nil, userInfo: message)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        setupWatchConnectivity()
        return true
    }

    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            let wcSession = WCSession.default
            wcSession.delegate = self
            if wcSession.activationState != .activated {
                wcSession.activate()
            }
        }
    }
}
