import UIKit
import WatchConnectivity
import Foundation

enum Granularity {
    case character, word, line, sentenceCorrection
}

extension Notification.Name {
    static let didReceiveRotationData = Notification.Name("didReceiveRotationData")
}

class ViewController: UIViewController, UITextFieldDelegate, WCSessionDelegate, UIDocumentPickerDelegate {

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
    var wcSession: WCSession?
    private var lastGestureRecognized = false
    private var touchCoordinates: [String] = []
    private var gestureRecognition = GestureRecognition(bufferSize: 20)
    private var gestureCount = 0 // Track the number of gestures detected
    var selectedGranularity: Granularity = .character // Default granularity
    let t5Inference = T5Inference() // Create an instance of T5Inference
    var voiceRecognitionManager: SimpleVoiceRecognitionManager?
    var textErrorAnalyzer: TextErrorAnalyzer?
    

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
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
        
        setupSimpleVoiceRecognition()
            
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleVoiceOverFocusChanged(notification:)),
                                                   name: UIAccessibility.elementFocusedNotification,
                                                   object: nil)
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
        
        // Update voice recognition granularity
        voiceRecognitionManager?.setGranularity(selectedGranularity)
        
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
                if predicate.searchDirection == .next {
                    // For forward movement - select the character we're moving into
                    if let currentChar = textField.textRange(from: currentPosition, to: newPosition) {
                        textField.selectedTextRange = currentChar
                        
                        // Simply announce the character directly
                        if let selectedText = textField.text(in: currentChar) {
                            textField.announceSelectedTextOnly()
                        }
                        print("Selected character after cursor (forward).")
                    } else {
                        textField.selectedTextRange = textField.textRange(from: newPosition, to: newPosition)
                        print("Moved cursor by character to new position (no selection).")
                    }
                } else {
                    // For backward movement - select the character we're moving into
                    if let previousPosition = textField.position(from: currentPosition, offset: -1) {
                        if let previousChar = textField.textRange(from: previousPosition, to: currentPosition) {
                            textField.selectedTextRange = previousChar
                            
                            // Simply announce the character
                            textField.announceSelectedTextOnly()
                            print("Selected character before cursor (backward).")
                        } else {
                            textField.selectedTextRange = textField.textRange(from: newPosition, to: newPosition)
                            print("Moved cursor by character to new position (no selection).")
                        }
                    } else {
                        textField.selectedTextRange = textField.textRange(from: newPosition, to: newPosition)
                        print("Moved cursor by character to new position (no selection at boundary).")
                    }
                }
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
                    
                    // Simply announce the selected text
                    textField.announceSelectedTextOnly()
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

// Add crown rotation handling
private func handleCrownRotation(delta: Double) {
    // Ensure text field has focus
    if !userInputTextField.isFirstResponder {
        userInputTextField.becomeFirstResponder()
        return
    }
    
    // Create a search predicate with direction based on crown rotation
    let searchDirection: UIAccessibilityCustomRotor.Direction = delta > 0 ? .next : .previous
    let predicate = UIAccessibilityCustomRotorSearchPredicate()
    predicate.searchDirection = searchDirection
    
    // Use existing moveCursor method with current granularity
    print("Moving cursor with crown: direction=\(searchDirection), granularity=\(selectedGranularity)")
    _ = moveCursor(in: userInputTextField, for: predicate, granularity: selectedGranularity)
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
        print("DEBUG: iPhone received message: \(message)")
        
        // Handle motion status updates
        if let motionStatus = message["motionStatus"] as? String {
            print("Received motion status update: \(motionStatus)")
            return
        }
        
        // Handle voice commands
        if let voiceCommand = message["voiceCommand"] as? String {
            print("Voice: Received voice command from watch: \(voiceCommand)")
            
            DispatchQueue.main.async { [weak self] in
                self?.processWatchVoiceCommand(from: message)
            }
            return
        }
        
        // Handle gyroscope rotation data
        if let rotationRateX = message["rotationRateX"] as? Double,
           let rotationRateY = message["rotationRateY"] as? Double,
           let rotationRateZ = message["rotationRateZ"] as? Double {
            
            if isRecognitionMode {
                let gestureRecognized = gestureRecognition.addGyroData(
                    rotationRateX: rotationRateX,
                    rotationRateY: rotationRateY,
                    rotationRateZ: rotationRateZ
                )
                
                if gestureRecognized {
                    if !lastGestureRecognized {
                        handleGestureRecognition()
                    }
                    lastGestureRecognized = true
                } else {
                    lastGestureRecognized = false
                }
            } else if isRecording {
                gestureRecognition.addGyroData(
                    rotationRateX: rotationRateX,
                    rotationRateY: rotationRateY,
                    rotationRateZ: rotationRateZ
                )
            }
            
            NotificationCenter.default.post(
                name: .didReceiveRotationData,
                object: nil,
                userInfo: message
            )
        }
        // Handle crown rotation data
        else if let crownDelta = message["crownDelta"] as? Double {
            print("Received crown rotation delta: \(crownDelta)")
            
            // Process the crown rotation on the main thread
            DispatchQueue.main.async { [weak self] in
                self?.handleCrownRotation(delta: crownDelta)
            }
        }
    }

    /*private func moveToNextRotor() {
        guard let rotors = userInputTextField.accessibilityCustomRotors, !rotors.isEmpty else {
            print("No custom rotors available.")
            return
        }

        currentRotorIndex = (currentRotorIndex + 1) % rotors.count
        let nextRotor = rotors[currentRotorIndex]
        
        UIAccessibility.post(notification: .announcement, argument: nextRotor.name)
        // The rotor will change based on the announcement, we assume here
    }*/

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

        print("Slider changed to option: \(selectedOption)") // Debug print
        updateSliderValueLabel()

        updateOptionDisplay() // This should set userInputTextField.text
        print("userInputTextField.text = \(userInputTextField.text ?? "nil")") // Debug print
    }

    func updateSliderValueLabel() {
        sliderValueLabel.text = "Option \(selectedOption)"
    }
    

    func updateOptionDisplay() {
        let options = [
            "She went to the store yesterday.",  // Case 1: Missing "the"
            "She is going to buy new car next month.",  // Case 2: Missing "is"
            "They are waiting for bus at the corner.",  // Case 3: Missing "are" and "the"
            "He gave me the book yesterday.",  // Case 4: "gived" -> "gave"
            "We bought groceries for dinner tonight.",  // Case 5: "buyed" -> "bought"
            "The students wrote their essays last week.",  // Case 6: "writed" -> "wrote"
            "My sister works at the hospital downtown.",  // Case 7: Extra "she"
            "The document that I wrote contains important information.",  // Case 8: Extra "it"
            "When the professor explained the concept, I understood it.",  // Case 9: Extra "he"
            "John is going to visit his parents tomorrow.",  // Case 10: Extra "he" and "to"
            "The weather forecast for NYC this weekend shows temperatures dropping to 40 degrees with possibility of precipitation on Saturday. We recommend bringing an umbrella and wearing warm clothes when venturing outdoors. The city's park's will remain open but outdoor events may be canceled due to the unfavorable conditions."

        ]
        
        let incorrectSentences = [
            "She went to store yesterday.",  // Case 1: Missing "the"
            "She going to buy new car next month.",  // Case 2: Missing "is"
            "They waiting for bus at corner.",  // Case 3: Missing "are" and "the"
            "He gived me the book yesterday.",  // Case 4: "gived" -> "gave"
            "We buyed groceries for dinner tonight.",  // Case 5: "buyed" -> "bought"
            "The students writed their essays last week.",  // Case 6: "writed" -> "wrote"
            "My sister she works at the hospital downtown.",  // Case 7: Extra "she"
            "The document that I wrote it contains important information.",  // Case 8: Extra "it"
            "When the professor he explained the concept, I understood it.",  // Case 9: Extra "he"
            "John he is going to to visit his parents tomorrow.",  // Case 10: Extra "he" and "to"
            ""
        ]
        
        messageLabel.text = options[selectedOption - 1]
        userInputTextField.text = incorrectSentences[selectedOption - 1]
        
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

    // Call this function when view loads or when any changes are needed
}

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
