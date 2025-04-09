import UIKit
import WatchConnectivity
import Speech

// Extension to add improved voice control functionality to ViewController
extension ViewController {
    
    // MARK: - Setup
    
    func setupSimpleVoiceRecognition() {
        // Initialize text error analyzer with the existing T5Inference instance
        self.textErrorAnalyzer = TextErrorAnalyzer(t5Inference: t5Inference)
        print("Voice: Created TextErrorAnalyzer with existing T5Inference instance")
        
        // Create voice recognition manager with text field and analyzer
        voiceRecognitionManager = SimpleVoiceRecognitionManager(textField: userInputTextField, errorAnalyzer: self.textErrorAnalyzer)
        
        // Listen for voice recognition notifications
        setupVoiceRecognitionObservers()
        
        print("Voice: Simple voice recognition manager setup complete with error analysis capability")
    }
    
    private func setupVoiceRecognitionObservers() {
        // Add observers for voice recognition events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVoiceRecognitionStarted),
            name: NSNotification.Name("VoiceRecognitionDidStart"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVoiceRecognitionStopped),
            name: NSNotification.Name("VoiceRecognitionDidStop"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVoiceRecognitionError(_:)),
            name: NSNotification.Name("VoiceRecognitionError"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVoiceRecognitionResult(_:)),
            name: NSNotification.Name("VoiceRecognitionResultProcessed"),
            object: nil
        )
    }
    
    // MARK: - Voice Control Actions
    
    func startVoiceRecognition() {
        print("Voice: Starting voice recognition from watch request")
        
        // Show visual feedback
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Haptic feedback for blind users
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Announce via VoiceOver
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: "Listening for voice commands")
            }
            
            // Start voice recognition with current granularity
            self.voiceRecognitionManager?.startListening(withGranularity: self.selectedGranularity)
            
            // Update watch about status
            self.sendVoiceStatusToWatch(status: "listening")
        }
    }
    
    func stopVoiceRecognition() {
        print("Voice: Stopping voice recognition from watch request")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Stop recognition
            self.voiceRecognitionManager?.stopListening()
            
            // Reset UI
            self.updateOptionDisplay()
            
            // Announce via VoiceOver
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: "Voice recognition stopped")
            }
            
            // Update watch
            self.sendVoiceStatusToWatch(status: "stopped")
        }
    }
    
    // MARK: - Watch Communication
    
    func sendVoiceStatusToWatch(status: String, text: String? = nil, error: String? = nil) {
        guard let session = wcSession else {
            print("Voice: WCSession not available")
            return
        }
        
        if !session.isReachable {
            print("Voice: Watch not reachable")
            return
        }
        
        var message: [String: Any] = ["voiceStatus": status]
        
        if let text = text {
            message["recognizedText"] = text
        }
        
        if let error = error {
            message["errorMessage"] = error
        }
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("Voice: Failed to send status to watch: \(error.localizedDescription)")
        }
    }
    
    // Process voice commands from watch
    func processWatchVoiceCommand(from message: [String: Any]) {
        if let voiceCommand = message["voiceCommand"] as? String {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                switch voiceCommand {
                case "startListening":
                    self.startVoiceRecognition()
                case "stopListening":
                    // Add a small delay to allow final recognition processing to complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.stopVoiceRecognition()
                    }
                default:
                    print("Voice: Unknown voice command from watch: \(voiceCommand)")
                }
            }
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc func handleVoiceRecognitionStarted() {
        print("Voice: Recognition started notification received")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Inform watch
            self.sendVoiceStatusToWatch(status: "listening")
        }
    }
    
    @objc func handleVoiceRecognitionStopped() {
        print("Voice: Recognition stopped notification received")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Restore normal UI
            self.updateOptionDisplay()
            
            // Inform watch
            self.sendVoiceStatusToWatch(status: "stopped")
        }
    }
    
    @objc func handleVoiceRecognitionError(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let errorMessage = userInfo["error"] as? String else {
            return
        }
        
        print("Voice: Recognition error: \(errorMessage)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Announce to VoiceOver
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: "Voice recognition error: \(errorMessage)")
            }
            
            // Inform watch
            self.sendVoiceStatusToWatch(status: "error", error: errorMessage)
            
            // Reset UI after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.updateOptionDisplay()
            }
        }
    }
    
    @objc func handleVoiceRecognitionResult(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let operation = userInfo["operation"] as? String,
              let content = userInfo["content"] as? String else {
            return
        }
        
        print("Voice: Recognition result: operation=\(operation), content=\(content)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Set the flag to indicate text was modified by voice
            self.textModifiedByVoice = true
            
            // Update UI to show success
            let operationName = operation.isEmpty ? "unknown" : operation
            let successMessage = "Voice command: \(operationName) \(content)"
            //self.messageLabel.text = successMessage
            
            // Inform watch with recognized text
            self.sendVoiceStatusToWatch(status: "recognized", text: content)
            
            // Reset just the message label after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                // Just update the message label, not the text field
                //self.messageLabel.text = "Voice command processed"
                //self.messageLabel.textColor = .black
            }
        }
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // Set the flag to indicate text was modified manually
        textModifiedByVoice = true
        return true
    }
}
