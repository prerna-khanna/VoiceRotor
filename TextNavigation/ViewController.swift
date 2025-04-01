import UIKit
import WatchConnectivity
import Foundation

enum Granularity {
    case character, word, line, sentenceCorrection
}


extension Notification.Name {
    static let didReceiveRotationData = Notification.Name("didReceiveRotationData")
}

class ViewController: UIViewController, UITextFieldDelegate, WCSessionDelegate, UIDocumentPickerDelegate, WatchCrownNavigatorDelegate {

    @IBOutlet weak var userIdTextField: UITextField!
    @IBOutlet weak var recordSwitch: UISwitch!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var userInputTextField: UITextField!
    @IBOutlet weak var optionSlider: UISlider!
    @IBOutlet weak var sliderValueLabel: UILabel!
    @IBOutlet weak var modeSwitch: UISwitch!
    @IBOutlet weak var recordButton: UIButton!

    var isRecording = false
    var isRecognitionMode = true
    var selectedOption: Int = 1
    private var wcSession: WCSession?
    private var lastGestureRecognized = false
    private var touchCoordinates: [String] = []
    private var gestureRecognition = GestureRecognition(bufferSize: 20)
    private var gestureCount = 0 // Track the number of gestures detected
    private var selectedGranularity: Granularity = .character // Default granularity
    private let t5Inference = T5Inference() // Create an instance of T5Inference
    
    // Crown navigation properties
    private var watchCrownNavigator: WatchCrownNavigator?
    private var lastCrownMovementTime: Date = Date()
    private let crownMovementThreshold: TimeInterval = 0.05 // Adjust sensitivity as needed

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        // Initialize watch crown navigator
        watchCrownNavigator = WatchCrownNavigator()
        watchCrownNavigator?.delegate = self
        
        // Load the model when the app starts
        t5Inference.loadModel { success in
            if success {
                print("Model loaded successfully.")
            } else {
                print("Failed to load the model.")
            }
        }
        
        setupRotationDataObserver()
        setupWatchConnectivity()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleVoiceOverFocusChanged(notification:)),
                                               name: UIAccessibility.elementFocusedNotification,
                                               object: nil)
                                               
        updateFonts()

        setupHideKeyboardOnTap()
        setupCustomActionRotor()

        userInputTextField.delegate = self // Set the delegate for the text field

        modeSwitch.addTarget(self, action: #selector(modeSwitchToggled), for: .valueChanged)
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        recordSwitch.addTarget(self, action: #selector(toggleRecording(_:)), for: .valueChanged)

        // Continuously monitor text field interaction
        monitorTextFieldInteraction()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Programmatically select the custom action rotor when the app becomes active
        print("App has appeared. Re-selecting Custom Action rotor.")
        reselectCustomActionRotor()
    }

    private func setupCustomActionRotor() {
        let customActionRotor = UIAccessibilityCustomRotor(name: "Custom Action") { predicate in
            print("Custom Action rotor selected with granularity: \(self.selectedGranularity)")
            return self.moveCursor(in: self.userInputTextField, for: predicate, granularity: self.selectedGranularity)
        }

        userInputTextField.accessibilityCustomRotors = [customActionRotor]
        print("Custom Action rotor added.")
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        print("Text field did begin editing. Re-selecting Custom Action rotor.")
        reselectCustomActionRotor()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        print("Text field did end editing.")
    }

    private func reselectCustomActionRotor() {
        if let customActionRotor = userInputTextField.accessibilityCustomRotors?.first(where: { $0.name == "Custom Action" }) {
            UIAccessibility.post(notification: .screenChanged, argument: customActionRotor.name)
            print("Custom Action rotor re-selected programmatically.")
        }
    }

    private func monitorTextFieldInteraction() {
        // Add target for all editing-related actions
        userInputTextField.addTarget(self, action: #selector(textFieldInteraction), for: .editingChanged)
        userInputTextField.addTarget(self, action: #selector(textFieldInteraction), for: .editingDidBegin)
        userInputTextField.addTarget(self, action: #selector(textFieldInteraction), for: .editingDidEnd)
    }

    @objc private func textFieldInteraction() {
        print("Text field interaction detected. Ensuring Custom Action rotor is active.")
        reselectCustomActionRotor()
    }

    @objc private func handleGestureRecognition() {
        self.gestureCount += 1

        if gestureCount > 4 {
            gestureCount = 1
        }

        print("Gesture recognized. Count: \(self.gestureCount)")

        switch gestureCount {
        case 1:
            selectedGranularity = .character
            print("Selected granularity: Character")
        case 2:
            selectedGranularity = .word
            print("Selected granularity: Word")
        case 3:
            selectedGranularity = .line
            print("Selected granularity: Line")
       case 4:
            selectedGranularity = .sentenceCorrection
            print("Selected granularity: Sentence Correction")
        default:
            selectedGranularity = .character
        }

        let rotorName = "Custom \(selectedGranularity)"
        UIAccessibility.post(notification: .announcement, argument: rotorName)
        print("\(rotorName) rotor selected programmatically.")

        reselectCustomActionRotor()
    }

    private func correctSentenceInTextField() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let text = self.userInputTextField.text, !text.isEmpty else {
                print("No text available for correction.")
                return
            }

            self.t5Inference.correctSentence(text) { correctedText in
                guard let correctedText = correctedText else {
                    print("Failed to correct the sentence.")
                    return
                }

                // Ensure UI updates are done on the main thread
                DispatchQueue.main.async {
                    self.userInputTextField.text = correctedText
                    print("Corrected sentence: \(correctedText)")
                }
            }
        }
    }

    private func moveCursor(in textField: UITextField, for predicate: UIAccessibilityCustomRotorSearchPredicate, granularity: Granularity) -> UIAccessibilityCustomRotorItemResult? {
        guard let textRange = textField.selectedTextRange else {
            print("No selected text range.")
            return nil
        }

        var currentPosition = predicate.searchDirection == .next ? textRange.end : textRange.start
        let offset = predicate.searchDirection == .next ? 1 : -1

        print("Moving cursor in direction: \(predicate.searchDirection == .next ? "Next" : "Previous") with granularity: \(granularity)")

        switch granularity {
        case .character:
            if let newPosition = textField.position(from: currentPosition, offset: offset) {
                textField.selectedTextRange = textField.textRange(from: newPosition, to: newPosition)
                print("Moved cursor by character to new position.")
                return UIAccessibilityCustomRotorItemResult(targetElement: textField, targetRange: textField.selectedTextRange)
            }
        case .word, .line:
            let direction: UITextDirection = predicate.searchDirection == .next ? UITextDirection.storage(.forward) : UITextDirection.storage(.backward)
            let boundary: UITextGranularity = (granularity == .word) ? .word : .line

            while true {
                if let newRange = textField.tokenizer.rangeEnclosingPosition(currentPosition, with: boundary, inDirection: direction) {
                    if (predicate.searchDirection == .next && newRange.start == currentPosition) ||
                       (predicate.searchDirection == .previous && newRange.end == currentPosition) {
                        if let adjustedPosition = textField.position(from: currentPosition, offset: offset) {
                            currentPosition = adjustedPosition
                            print("Adjusted position due to no movement. Current position: \(currentPosition)")
                            continue
                        } else {
                            break
                        }
                    }
                    textField.selectedTextRange = newRange
                    print("Moved cursor by \(granularity) to new range.")
                    return UIAccessibilityCustomRotorItemResult(targetElement: textField, targetRange: newRange)
                } else {
                    if let adjustedPosition = textField.position(from: currentPosition, offset: offset) {
                        currentPosition = adjustedPosition
                        print("Adjusted position due to no range found. Current position: \(currentPosition)")
                        continue
                    } else {
                        break
                    }
                }
            }
        case .sentenceCorrection:
            if predicate.searchDirection == .next {
                print("Sentence correction triggered, correcting sentence.")
                let sentenceToCorrect = textField.text ?? ""
                t5Inference.correctSentence(sentenceToCorrect) { [weak self] correctedSentence in
                    guard let self = self else { return }
                    if let correctedSentence = correctedSentence {
                        print("Corrected sentence: \(correctedSentence)")
                        DispatchQueue.main.async {
                            self.userInputTextField.text = correctedSentence
                            self.moveCursorToEnd()
                        }
                    } else {
                        print("Failed to correct the sentence.")
                    }
                }
            } else {
                print("Sentence correction canceled, no changes made.")
            }
            return nil
        }

        print("Failed to move the cursor.")
        return nil
    }

    private func moveCursorToEnd() {
        let endPosition = userInputTextField.endOfDocument
        userInputTextField.selectedTextRange = userInputTextField.textRange(from: endPosition, to: endPosition)
        print("Cursor moved to end of text.")
    }

    @objc private func handleVoiceOverFocusChanged(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let focusedElement = userInfo[UIAccessibility.focusedElementUserInfoKey] as? UIView else {
            return
        }

        let point = focusedElement.accessibilityActivationPoint
        print("VoiceOver focused on element at X: \(point.x), Y: \(point.y)")
    }

    @objc private func toggleRecording(_ sender: UISwitch) {
        isRecording = sender.isOn
        if !isRecording {
            saveCoordinatesToFile()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        recordTouches(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        recordTouches(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        recordTouches(touches)
    }

    private func recordTouches(_ touches: Set<UITouch>) {
        guard isRecording, let touch = touches.first else { return }
        let position = touch.location(in: view)
        let coordinate = "Touch X: \(position.x), Y: \(position.y)"
        touchCoordinates.append(coordinate)
        print(coordinate)
    }

    private func saveCoordinatesToFile() {
        guard let userId = userIdTextField.text, !userId.isEmpty else {
            print("User ID is empty")
            return
        }
        if touchCoordinates.isEmpty {
            print("No coordinates to save")
            return
        }

        let fileName = "User_\(userId)_Option\(selectedOption).txt"
        let tempDirectory = FileManager.default.temporaryDirectory
        let filePath = tempDirectory.appendingPathComponent(fileName)

        do {
            try touchCoordinates.joined(separator: "\n").write(to: filePath, atomically: true, encoding: .utf8)
            print("Coordinates saved to temporary file: \(filePath)")
            presentDocumentPicker(for: filePath)
        } catch {
            print("Failed to save coordinates: \(error.localizedDescription)")
        }
    }

    private func saveRecordedDataToCSV(data: [Double]) {
        guard let userId = userIdTextField.text, !userId.isEmpty else {
            print("User ID is empty")
            return
        }
        if data.isEmpty {
            print("No gesture data to save")
            return
        }

        let fileName = "GestureData_User_\(userId)_Option\(selectedOption).csv"
        let tempDirectory = FileManager.default.temporaryDirectory
        let filePath = tempDirectory.appendingPathComponent(fileName)

        let csvText = data.map { "\($0)" }.joined(separator: "\n")

        do {
            try csvText.write(to: filePath, atomically: true, encoding: .utf8)
            print("Gesture data saved to temporary file: \(filePath)")
            presentDocumentPicker(for: filePath)
        } catch {
            print("Failed to save gesture data: \(error.localizedDescription)")
        }
    }

    private func presentDocumentPicker(for fileURL: URL) {
        let documentPicker = UIDocumentPickerViewController(forExporting: [fileURL])
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .formSheet
        present(documentPicker, animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            print("File saved to: \(url)")
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("Document picker was cancelled.")
    }

    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            wcSession = WCSession.default
            wcSession?.delegate = self
            wcSession?.activate()
        }
    }

    @objc private func modeSwitchToggled() {
        isRecognitionMode = modeSwitch.isOn
        recordButton.isEnabled = !isRecognitionMode
        messageLabel.text = isRecognitionMode ? "Recognition Mode" : "Recording Mode"
        print("Switched to \(isRecognitionMode ? "Recognition" : "Recording") Mode")
    }

    @objc private func recordButtonTapped() {
        if isRecording {
            isRecording = false
            let recordedTemplate = gestureRecognition.stopRecording()
            saveRecordedDataToCSV(data: recordedTemplate)
            recordButton.setTitle("Start Recording", for: .normal)
            print("Gesture recording stopped and saved.")
        } else {
            isRecording = true
            gestureRecognition.startRecording()
            recordButton.setTitle("Stop Recording", for: .normal)
            print("Gesture recording started.")
        }
    }

    private func setupRotationDataObserver() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleRotationData(notification:)),
                                               name: .didReceiveRotationData,
                                               object: nil)
    }

    @objc private func handleRotationData(notification: Notification) {
        guard let rotationData = notification.userInfo as? [String: Double] else {
            print("Invalid rotation data received.")
            return
        }
    }

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

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // Handle rotation data from the watch
        if let rotationRateX = message["rotationRateX"] as? Double,
           let rotationRateY = message["rotationRateY"] as? Double,
           let rotationRateZ = message["rotationRateZ"] as? Double {

            if isRecognitionMode {
                let gestureRecognized = gestureRecognition.addGyroData(rotationRateX: rotationRateX, rotationRateY: rotationRateY, rotationRateZ: rotationRateZ)
                
                if gestureRecognized {
                    if !lastGestureRecognized {
                        handleGestureRecognition()
                    }
                    lastGestureRecognized = true
                } else {
                    lastGestureRecognized = false
                }
            } else if isRecording {
                gestureRecognition.addGyroData(rotationRateX: rotationRateX, rotationRateY: rotationRateY, rotationRateZ: rotationRateZ)
            }

            NotificationCenter.default.post(name: .didReceiveRotationData, object: nil, userInfo: message)
        }
        // Handle crown rotation data
        else if let crownDelta = message["crownDelta"] as? Double {
            print("Received crown delta: \(crownDelta)")
            
            // Only process crown movements if enough time has passed since the last movement
            // This helps prevent too rapid text navigation
            let now = Date()
            if now.timeIntervalSince(lastCrownMovementTime) >= crownMovementThreshold {
                lastCrownMovementTime = now
                
                // Determine direction based on crown rotation
                let direction: NavigationDirection = crownDelta > 0 ? .forward : .backward
                
                // Use magnitude for "how far" to move (can be used for acceleration)
                let magnitude = min(1.0, abs(crownDelta))
                
                // Process the crown movement
                DispatchQueue.main.async { [weak self] in
                    self?.processCrownMovement(direction: direction, magnitude: magnitude)
                }
            }
        } else {
            print("Received message with unknown data.")
        }
    }
    
    // Process crown movement to navigate text
    private func processCrownMovement(direction: NavigationDirection, magnitude: Double) {
        // Determine search direction for accessibility rotor
        let searchDirection: UIAccessibilityCustomRotor.Direction =
            direction == .forward ? .next : .previous
        
        // Create a predicate for the search - use the no-parameter initializer
        let predicate = UIAccessibilityCustomRotorSearchPredicate()
        predicate.searchDirection = searchDirection
        
        // Use the existing moveCursor method with the selected granularity
        _ = moveCursor(in: userInputTextField, for: predicate, granularity: selectedGranularity)
    }
    
    // WatchCrownNavigatorDelegate methods
    func didNavigate(direction: NavigationDirection, magnitude: Double) {
        processCrownMovement(direction: direction, magnitude: magnitude)
    }
    
    func didDetectPauseAtPosition() {
        // Optional: Handle pause at a position (could trigger TTS or haptic feedback)
        print("Paused at current position")
    }

    func setupHideKeyboardOnTap() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(hideKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    @objc func hideKeyboard() {
        view.endEditing(true)
    }

    func setupUI() {
        recordSwitch.isOn = false
        userIdTextField.delegate = self
        userInputTextField.delegate = self
        setupSlider()
    }

    func setupSlider() {
        optionSlider.minimumValue = 1
        optionSlider.maximumValue = 11
        optionSlider.value = 1
        optionSlider.isContinuous = true
        updateSliderValueLabel()
    }

    @IBAction func sliderValueChanged(_ sender: UISlider) {
        let roundedValue = round(sender.value)
        sender.value = roundedValue
        selectedOption = Int(roundedValue)
        updateOptionDisplay()
        updateSliderValueLabel()
        userInputTextField.text = ""
    }

    func updateSliderValueLabel() {
        sliderValueLabel.text = "Option \(selectedOption)"
    }

    func updateOptionDisplay() {
        let options = [
        "I have apples.",
        "Let me know if you need anything else.",
           "David, Cindy and Mary will each report to the office of the chairman.",
           "About 10 Jordanian doctors arrived at the hospital a few days ago.",
           "Is this the only time available?",
           "If so he probably will have to pay back.",
           
            "See what concerts we have for you in your city.",
            "The injury is more serious than the Panthers first expected.",
            "History repeated itself last season when Barcelona beat Madrid.",
            "The law enforcement has a responsibility for the safety of the public.",
            "He pleaded guilty in February under an agreement with the government."
        ]
        
        messageLabel.text = options[selectedOption - 1]
    }
    
    private func updateFonts() {
    // Update font for UILabel
    messageLabel.font = UIFont.preferredFont(forTextStyle: .body)

    // Update font for UITextField
    userIdTextField.font = UIFont.preferredFont(forTextStyle: .body)
    userInputTextField.font = UIFont.preferredFont(forTextStyle: .body)

    // Update font for UISwitch if there are any labels
    // UISwitch doesn't have a font itself, but associated labels might

    // Update font for UIButton
    recordButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)

    // Update font for other UI elements like UISlider labels
    sliderValueLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
