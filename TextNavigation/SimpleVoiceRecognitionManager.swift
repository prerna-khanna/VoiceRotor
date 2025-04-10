import Foundation
import Speech
import AVFoundation
import UIKit

enum VoiceOperation: String {
    case type = "type"
    case delete = "delete"
    case insert = "insert"
    case replace = "replace"  // Added replace operation
    case bold = "bold"
    case italic = "italic"
    case underline = "underline"
    case clearFormat = "clear format"
    case space = "space"
    case period = "period"
    case comma = "comma"
    case question = "question"
    case exclamation = "exclamation"
    case newline = "newline"
    case read = "read"
    case unselect = "unselect"
    case cursorPosition = "cursor"
    case spell = "spell"
    case unknown
   
    // Parse from recognized text
    static func from(_ text: String) -> (operation: VoiceOperation, content: String?) {
        let lowerText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for command patterns - simple commands first
        if lowerText == "delete" || lowerText == "remove" {
            return (.delete, nil)
        }
        
        if lowerText == "read" || lowerText == "read text" || lowerText == "read all" {
            return (.read, nil)
        }
        
        if lowerText == "unselect" || lowerText == "deselect" || lowerText == "clear selection" {
            return (.unselect, nil)
        }
        
        if lowerText == "cursor" || lowerText == "cursor position" || lowerText == "where am i" {
            return (.cursorPosition, nil)
        }
        
        // Check for punctuation commands
        if lowerText == "space" {
            return (.space, nil)
        }
        
        if lowerText == "period" || lowerText == "dot" || lowerText == "full stop" {
            return (.period, nil)
        }
        
        if lowerText == "comma" || lowerText == "," {
            return (.comma, nil)
        }
        
        if lowerText == "question" || lowerText == "question mark" {
            return (.question, nil)
        }
        
        if lowerText == "exclamation" || lowerText == "exclamation mark" {
            return (.exclamation, nil)
        }
        
        if lowerText == "newline" || lowerText == "new line" || lowerText == "line break" {
            return (.newline, nil)
        }
        
        // Format commands
        if lowerText == "bold" {
            return (.bold, nil)
        }
        
        if lowerText == "italic" {
            return (.italic, nil)
        }
        
        if lowerText == "underline" {
            return (.underline, nil)
        }
        
        if lowerText == "clear format" || lowerText == "clear formatting" {
            return (.clearFormat, nil)
        }
        if lowerText == "spell" || lowerText == "spell out" || lowerText == "spell word" || lowerText == "spell letter by letter" {
                    return (.spell, nil)
                }
        
        // Commands with content
        if lowerText.hasPrefix("type ") {
            let content = String(lowerText.dropFirst("type ".count))
            return (.type, content)
        }
        
        if lowerText.hasPrefix("insert ") {
            //let prefix = lowerText.hasPrefix("insert ") ? "insert " : "add "
            let content = String(lowerText.dropFirst("insert ".count))
            return (.insert, content)
        }
        
        if lowerText.hasPrefix("replace ") {
            //let prefix = lowerText.hasPrefix("replace ") ? "replace " : "change "
            let content = String(lowerText.dropFirst("replace ".count))
            return (.replace, content)
        }
        
        // Default is to just type the content
        return (.unknown, lowerText)
    }
}

class SimpleVoiceRecognitionManager: NSObject {
    // MARK: - Properties
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var textErrorAnalyzer: TextErrorAnalyzer?
    private var lastRecognizedText: String = ""
    
    private let audioEngine = AVAudioEngine()
    
    // Private variables
    private var isListening = false
    private weak var textField: UITextField?
    private var selectedGranularity: Granularity = .character
    
    // MARK: - Setup
    
    init(textField: UITextField?, errorAnalyzer: TextErrorAnalyzer? = nil) {
        self.textField = textField
        self.textErrorAnalyzer = errorAnalyzer
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        
        // Request speech recognition authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                if status == .authorized {
                    print("Voice: Speech recognition authorized")
                } else {
                    print("Voice: Speech recognition not available (status: \(status.rawValue))")
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    func startListening(withGranularity granularity: Granularity = .character) {
        // Store current granularity
        self.selectedGranularity = granularity
        
        // First end any existing session
        if isListening {
            stopListening()
            
            // Add small delay before restarting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startRecording()
            }
            return
        }
        
        startRecording()
    }
    
    func stopListening() {
        guard isListening else { return }
        
        print("Voice: Stopping recognition")
        
        // Process last recognized text if available
        if !lastRecognizedText.isEmpty {
            print("Voice: Processing final recognized text before stopping: '\(lastRecognizedText)'")
            // Process directly without dispatch to async
            processRecognizedText(lastRecognizedText)
        }
        
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Stop audio engine and remove tap
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // End request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Reset audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Voice: Failed to deactivate audio session: \(error)")
        }
        
        isListening = false
        
        // Clear the last recognized text AFTER processing it
        lastRecognizedText = ""
        
        // Notify completion
        NotificationCenter.default.post(
            name: NSNotification.Name("VoiceRecognitionDidStop"),
            object: nil
        )
    }
    
    func setTextField(_ textField: UITextField?) {
        self.textField = textField
    }
    
    func setGranularity(_ granularity: Granularity) {
        self.selectedGranularity = granularity
    }
    
    // MARK: - Private Methods
    
    private func startRecording() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("Voice: Speech recognizer not available")
            return
        }
        
        // Configure audio session for recording
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Voice: Failed to configure audio session: \(error)")
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            print("Voice: Unable to create recognition request")
            return
        }
        
        // Configure for enhanced recognition (iOS 16+)
        if #available(iOS 16.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = true
            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.taskHint = .dictation
        } else {
            // Configure for partial results on older devices
            recognitionRequest.shouldReportPartialResults = true
        }
        
        // Setup audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            
            print("Voice: Started listening")
            isListening = true
            
            // Start recognition task
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                
                if let error = error {
                    // Check if it's just a cancellation error (which is normal)
                    let isCancellationError = (error as NSError).domain == "kAFAssistantErrorDomain" &&
                                             (error as NSError).code == 1 ||
                                             error.localizedDescription.contains("canceled")
                    
                    if !isCancellationError {
                        print("Voice: Recognition error: \(error.localizedDescription)")
                        
                        // Notify error
                        //NotificationCenter.default.post(
                            //name: NSNotification.Name("VoiceRecognitionError"),
                            //object: nil,
                            //userInfo: ["error": error.localizedDescription]
                        //)
                    } else {
                        print("Voice: Recognition stopped normally")
                        
                        // If we have a stored partial result and it was a cancellation, process it
                        if !self.lastRecognizedText.isEmpty {
                            print("Voice: Processing stored partial result: '\(self.lastRecognizedText)'")
                            self.processRecognizedText(self.lastRecognizedText)
                        }
                    }
                    return
                }
                
                if let result = result {
                    let recognizedText = result.bestTranscription.formattedString
                    print("Voice: Partial recognition: '\(recognizedText)'")
                    
                    // Store non-empty partial results
                    if !recognizedText.isEmpty {
                        self.lastRecognizedText = recognizedText
                    }
                    
                    // Process final result
                    if result.isFinal {
                        print("Voice: FINAL RESULT: '\(recognizedText)'")
                        
                        // Use the last valid partial result if final is empty
                        let textToProcess = recognizedText.isEmpty ? self.lastRecognizedText : recognizedText
                        
                        if !textToProcess.isEmpty {
                            print("Voice: Processing command: '\(textToProcess)'")
                            self.processRecognizedText(textToProcess)
                            
                            // Clear stored text after processing
                            self.lastRecognizedText = ""
                            
                            // Stop listening after processing a valid command
                            self.stopListening()
                        }
                    }
                }
            }
            
            // Notify started
            NotificationCenter.default.post(
                name: NSNotification.Name("VoiceRecognitionDidStart"),
                object: nil
            )
            
        } catch {
            print("Voice: Failed to start audio engine: \(error)")
        }
    }
    
    private func processRecognizedText(_ text: String) {
        print("Voice: Processing final text: '\(text)'")
        
        // Parse the voice operation
        let (operation, content) = VoiceOperation.from(text)
        
        // Process based on operation type
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let textField = self.textField else {
                print("Voice: TextField not available")
                return
            }
            
            // Make sure text field is active
            if !textField.isFirstResponder {
                textField.becomeFirstResponder()
            }
            
            print("Voice: Executing operation: \(operation.rawValue) with content: \(content ?? "none")")
            
            // Check if text is selected
            let hasSelection = !(textField.selectedTextRange?.isEmpty ?? true)
            
            switch operation {
            case .delete:
                self.performDelete(granularity: self.selectedGranularity)
                
            case .type:
                if let content = content {
                    self.performType(content: content)
                }
                
            case .insert:
                if let content = content {
                    self.performInsert(content, shouldReplace: false)
                }
                
            case .replace:
                if let content = content {
                    self.performInsert(content, shouldReplace: true)
                }
                
            // Handle punctuation operations
            case .space:
                self.insertSpecialCharacter(" ")
                
            case .period:
                self.insertSpecialCharacter(".")
                
            case .comma:
                self.insertSpecialCharacter(",")
                
            case .question:
                self.insertSpecialCharacter("?")
                
            case .exclamation:
                self.insertSpecialCharacter("!")
                
            case .newline:
                self.insertSpecialCharacter("\n")
                
            case .read:
                self.readTextField()
                
            case .unselect:
                self.unselectText()
                
            case .cursorPosition:
                self.announceCursorPosition()
            
            case .bold, .italic, .underline:
                // Only apply formatting if text is selected
                if hasSelection {
                    switch operation {
                    case .bold:
                        self.performFormatting(style: .bold)
                    case .italic:
                        self.performFormatting(style: .italic)
                    case .underline:
                        self.performFormatting(style: .underline)
                    default:
                        break
                    }
                } else {
                    // Announce that text must be selected for formatting
                    UIAccessibility.post(notification: .announcement,
                                        argument: "Select text first to apply formatting")
                }
                
            case .clearFormat:
                if hasSelection {
                    self.performClearFormatting()
                } else {
                    UIAccessibility.post(notification: .announcement,
                                        argument: "Select text first to clear formatting")
                }
                
            case .unknown:
                    // Announce that command is not recognized
                    UIAccessibility.post(notification: .announcement,
                                        argument: "Command not recognized. Try delete, type, insert, bold, italic, or underline")
                
            case .spell:
                self.spellOutSelectedText()
            }
            
            // Announce what happened for VoiceOver users
            self.announceVoiceOperationResult(operation, content: content)
            
            // Notify content update
            NotificationCenter.default.post(
                name: NSNotification.Name("VoiceRecognitionResultProcessed"),
                object: nil,
                userInfo: [
                    "operation": operation.rawValue,
                    "content": content ?? ""
                ]
            )
        }
    }
    
    private func spellOutSelectedText() {
           guard let textField = self.textField,
                 let selectedRange = textField.selectedTextRange else {
               return
           }
           
           // Check if there's a selection or just cursor position
           let hasSelection = !selectedRange.isEmpty
           
           if !hasSelection {
               // If no selection, try to get the word at cursor position
               if let wordRange = findWordRangeAroundCursor(in: textField) {
                   if let wordText = textField.text(in: wordRange) {
                       spellOutText(wordText)
                       return
                   }
               }
               
               // If no word found or couldn't get text, announce error
               UIAccessibility.post(notification: .announcement,
                                   argument: "No text selected to spell. Please select text first.")
               return
           }
           
           // If text is selected, get the selected text and spell it
           if let selectedText = textField.text(in: selectedRange) {
               spellOutText(selectedText)
           } else {
               UIAccessibility.post(notification: .announcement,
                                   argument: "Unable to get selected text to spell.")
           }
       }
       
       // Helper method to spell out text with proper pauses
       private func spellOutText(_ text: String) {
           if text.isEmpty {
               UIAccessibility.post(notification: .announcement,
                                   argument: "No text to spell.")
               return
           }
           
           // First announce that we're going to spell the text
           UIAccessibility.post(notification: .announcement,
                               argument: "Spelling: \(text)")
           
           // Wait a moment before spelling
           DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
               // Create the spelled version with pauses
               let letters = Array(text)
               var spelledText = ""
               
               // Build the spelled text with proper formatting
               for (index, letter) in letters.enumerated() {
                   let letterDescription: String
                   
                   if letter.isLetter {
                       // Handle special cases for better pronunciation
                       switch letter.lowercased() {
                       case "a": letterDescription = "A as in Alpha"
                       case "b": letterDescription = "B as in Bravo"
                       case "c": letterDescription = "C as in Charlie"
                       case "d": letterDescription = "D as in Delta"
                       case "e": letterDescription = "E as in Echo"
                       case "f": letterDescription = "F as in Foxtrot"
                       case "g": letterDescription = "G as in Golf"
                       case "h": letterDescription = "H as in Hotel"
                       case "i": letterDescription = "I as in India"
                       case "j": letterDescription = "J as in Juliet"
                       case "k": letterDescription = "K as in Kilo"
                       case "l": letterDescription = "L as in Lima"
                       case "m": letterDescription = "M as in Mike"
                       case "n": letterDescription = "N as in November"
                       case "o": letterDescription = "O as in Oscar"
                       case "p": letterDescription = "P as in Papa"
                       case "q": letterDescription = "Q as in Quebec"
                       case "r": letterDescription = "R as in Romeo"
                       case "s": letterDescription = "S as in Sierra"
                       case "t": letterDescription = "T as in Tango"
                       case "u": letterDescription = "U as in Uniform"
                       case "v": letterDescription = "V as in Victor"
                       case "w": letterDescription = "W as in Whiskey"
                       case "x": letterDescription = "X as in X-ray"
                       case "y": letterDescription = "Y as in Yankee"
                       case "z": letterDescription = "Z as in Zulu"
                       default: letterDescription = String(letter)
                       }
                   } else if letter.isNumber {
                       letterDescription = "Number \(letter)"
                   } else if letter == " " {
                       letterDescription = "Space"
                   } else {
                       // Handle punctuation and special characters
                       switch letter {
                       case ".": letterDescription = "Period"
                       case ",": letterDescription = "Comma"
                       case "?": letterDescription = "Question mark"
                       case "!": letterDescription = "Exclamation mark"
                       case ";": letterDescription = "Semicolon"
                       case ":": letterDescription = "Colon"
                       case "-": letterDescription = "Hyphen"
                       case "_": letterDescription = "Underscore"
                       case "/": letterDescription = "Slash"
                       case "\\": letterDescription = "Backslash"
                       case "'": letterDescription = "Single quote"
                       case "\"": letterDescription = "Double quote"
                       case "(": letterDescription = "Open parenthesis"
                       case ")": letterDescription = "Close parenthesis"
                       case "[": letterDescription = "Open bracket"
                       case "]": letterDescription = "Close bracket"
                       case "{": letterDescription = "Open brace"
                       case "}": letterDescription = "Close brace"
                       case "@": letterDescription = "At sign"
                       case "#": letterDescription = "Hash"
                       case "$": letterDescription = "Dollar sign"
                       case "%": letterDescription = "Percent"
                       case "^": letterDescription = "Caret"
                       case "&": letterDescription = "Ampersand"
                       case "*": letterDescription = "Asterisk"
                       case "+": letterDescription = "Plus"
                       case "=": letterDescription = "Equals"
                       case "<": letterDescription = "Less than"
                       case ">": letterDescription = "Greater than"
                       case "|": letterDescription = "Pipe"
                       case "~": letterDescription = "Tilde"
                       default: letterDescription = "Symbol \(letter)"
                       }
                   }
                   
                   // Add letter number for reference
                   spelledText += "Letter \(index + 1): \(letterDescription)."
                   
                   // Schedule each letter announcement with appropriate delay
                   let delay = 1.0 + Double(index) * 2.5
                   
                   DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                       UIAccessibility.post(notification: .announcement,
                                           argument: "Letter \(index + 1): \(letterDescription)")
                   }
               }
               
               // Schedule final announcement
               let finalDelay = 1.0 + Double(letters.count) * 2.5 + 1.0
               DispatchQueue.main.asyncAfter(deadline: .now() + finalDelay) {
                   UIAccessibility.post(notification: .announcement,
                                       argument: "End of spelling.")
               }
           }
       }

        // Refactored insert method to handle both insert and replace
    private func performInsert(_ content: String, shouldReplace: Bool = true) {
        guard let textField = self.textField,
              let selectedRange = textField.selectedTextRange else {
            return
        }
        
        // Determine if text is selected (not just a cursor position)
        let hasSelection = !selectedRange.isEmpty
        
        // Handle based on granularity
        switch selectedGranularity {
        case .character:
            if hasSelection && !shouldReplace {
                // For insert in character mode with a selection: insert AFTER the selection
                let insertPosition = selectedRange.end // Changed to .end to insert after selection
                
                // Create a new range just at the position after the selection
                if let emptyRange = textField.textRange(from: insertPosition, to: insertPosition) {
                    // Insert the content after the selection
                    textField.replace(emptyRange, withText: content)
                }
            } else {
                // For replace in character mode or no selection: replace the selection with content
                textField.replace(selectedRange, withText: content)
            }
            
        case .word, .line, .sentenceCorrection:
            if hasSelection && !shouldReplace {
                // For insert in word/line mode with a selection
                
                // Insert content AFTER the selection with proper spacing
                let insertPosition = selectedRange.end // Changed to .end to insert after selection
                
                if let insertRange = textField.textRange(from: insertPosition, to: insertPosition) {
                    // Add space before inserted content if it doesn't start with space
                    // and we're not at the beginning of text
                    var contentWithSpace = content
                    
                    // For word granularity, handle spacing correctly
                    if selectedGranularity == .word {
                        // Add leading space if needed (if we're not at the end of text
                        // and not after a space already)
                        let needsLeadingSpace = insertPosition != textField.beginningOfDocument &&
                                               !contentWithSpace.hasPrefix(" ")
                                               
                        if needsLeadingSpace {
                            // Check if there's already a space before where we're inserting
                            if let beforePos = textField.position(from: insertPosition, offset: -1),
                               let beforeRange = textField.textRange(from: beforePos, to: insertPosition),
                               let charBefore = textField.text(in: beforeRange),
                               !charBefore.hasPrefix(" ") {
                                contentWithSpace = " " + contentWithSpace
                            }
                        }
                        
                        // Add trailing space if needed
                        if !contentWithSpace.hasSuffix(" ") && insertPosition != textField.endOfDocument {
                            contentWithSpace += " "
                        }
                    }
                    
                    // Insert at the position after selection
                    textField.replace(insertRange, withText: contentWithSpace)
                }
            } else {
                // For replace in word/line mode or no selection: replace the selection with content
                
                // Add space if needed for replacement (for word granularity)
                var replacementText = content
                
                // Only add space for word granularity and if we're not at the end of text
                if selectedGranularity == .word &&
                   selectedRange.end != textField.endOfDocument &&
                   !content.hasSuffix(" ") {
                    replacementText += " "
                }
                
                textField.replace(selectedRange, withText: replacementText)
            }
        }
    }
    
    // MARK: - Text Operations
    
    private func performDelete(granularity: Granularity) {
        guard let textField = self.textField,
              let selectedRange = textField.selectedTextRange else {
            return
        }
        
        switch granularity {
        case .character:
            // Delete a character
            if selectedRange.isEmpty {
                // If no selection, delete the character before the cursor
                if let newStart = textField.position(from: selectedRange.start, offset: -1) {
                    if let rangeToDelete = textField.textRange(from: newStart, to: selectedRange.start) {
                        textField.replace(rangeToDelete, withText: "")
                    }
                }
            } else {
                // Delete the selection
                textField.replace(selectedRange, withText: "")
            }
            
        case .word:
            // Delete a word
            if selectedRange.isEmpty {
                // If no selected word, find the word boundary
                if let wordRange = findWordRangeAroundCursor(in: textField) {
                    textField.replace(wordRange, withText: "")
                }
            } else {
                // Delete the selection
                textField.replace(selectedRange, withText: "")
            }
            
        case .line, .sentenceCorrection:
            // Delete the entire line/sentence
            if let _ = textField.text {
                textField.text = ""
            }
        }
    }
    
    // Now appends to existing text instead of replacing it
    private func performType(content: String) {
        guard let textField = self.textField else { return }
        
        // For "type" command, append text to existing content
        let currentText = textField.text ?? ""
        
        // Append new text
        textField.text = currentText + (currentText.isEmpty ? "" : " ") + content
        
        // Move cursor to end
        let endPosition = textField.endOfDocument
        textField.selectedTextRange = textField.textRange(from: endPosition, to: endPosition)
    }
    
    // Simple append function (used by unknown commands)
    private func performAppend(_ content: String) {
        guard let textField = self.textField else { return }
        
        // Get current cursor position
        guard let selectedRange = textField.selectedTextRange else {
            // If no cursor, just append to the end
            let currentText = textField.text ?? ""
            textField.text = currentText + (currentText.isEmpty ? "" : " ") + content
            return
        }
        
        // Insert at current position
        textField.replace(selectedRange, withText: content)
    }
    
    private func performInsert(_ content: String) {
        guard let textField = self.textField,
              let selectedRange = textField.selectedTextRange else {
            return
        }
        
        // Insert at current position
        textField.replace(selectedRange, withText: content)
    }
    
    // Method to insert special characters (punctuation)
    private func insertSpecialCharacter(_ character: String) {
        guard let textField = self.textField,
              let selectedRange = textField.selectedTextRange else {
            return
        }
        
        // Insert the character at the current position
        textField.replace(selectedRange, withText: character)
    }
    
    // Method to unselect text and place cursor at the end of selection
    private func unselectText() {
        guard let textField = self.textField,
              let selectedRange = textField.selectedTextRange else {
            return
        }
        
        // Check if text is actually selected
        if selectedRange.isEmpty {
            UIAccessibility.post(notification: .announcement, argument: "No text is selected")
            return
        }
        
        // Move cursor to the end of the current selection
        let endPosition = selectedRange.end
        textField.selectedTextRange = textField.textRange(from: endPosition, to: endPosition)
        
        // Announce success
        UIAccessibility.post(notification: .announcement, argument: "Selection cleared, cursor placed after selection")
    }
    
    // Method to read the text field with improved functionality
    private func readTextField() {
        guard let textField = self.textField else {
            return
        }
        
        let text = textField.text ?? ""
        
        if text.isEmpty {
            // If the text field is empty, announce that
            UIAccessibility.post(notification: .announcement, argument: "Text field is empty")
            return
        }
        
        print("Voice: Reading text field with intelligent error detection")
        
        // First announce that we're going to read the text
        UIAccessibility.post(notification: .announcement, argument: "Reading text")
        
        // Wait a moment before reading the actual content
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Now read the actual text content
            UIAccessibility.post(notification: .announcement, argument: text)
            
            // Then analyze for errors after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self else { return }
                print("Voice: Analyzing text for errors: \"\(text)\"")
                
                self.textErrorAnalyzer?.analyzeText(text) { [weak self] errors in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        // Make sure we actually have the text field and we're still analyzing the same text
                        guard let currentTextField = self.textField, currentTextField.text == text else {
                            print("Voice: Text field or content changed during analysis, aborting error reading.")
                            return
                        }
                        
                        if errors.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                UIAccessibility.post(notification: .announcement, argument: "No errors detected in the text.")
                                print("Voice: No errors detected in the text")
                            }
                        } else {
                            print("Voice: Found \(errors.count) errors to announce")
                            
                            // First announce how many errors were found
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                let introMessage = "Found \(errors.count) potential \(errors.count == 1 ? "issue" : "issues") in the text."
                                UIAccessibility.post(notification: .announcement, argument: introMessage)
                                print("Voice: Announced: \(introMessage)")
                                
                                // Then schedule announcements for each error
                                self.scheduleErrorAnnouncements(errors)
                            }
                        }
                    }
                }
            }
        }
    }

    // Helper to announce each error in sequence with proper timing
    // In SimpleVoiceRecognitionManager.swift

    private func scheduleErrorAnnouncements(_ errors: [DetectedError]) {
        print("Voice: Scheduling announcements for \(errors.count) errors")
        // Schedule each error announcement with increasing delays
        for (index, error) in errors.enumerated() {
            // Calculate delay: 2 seconds base + 3 seconds per previous error
            let delay = 2.0 + (Double(index) * 3.0)

            // --- START MODIFICATION ---
            // Create announcement text WITHOUT the error type prefix
            var announcement = "Error \(index + 1): "
            if let errorText = error.errorText, let correction = error.correction {

                // Check for the special "missing word" / "extra word" formats
                // potentially generated by the updated TextErrorAnalyzer (paste-8.txt)
                if errorText.starts(with: "missing word") {
                    // Extract context if available from the errorText placeholder
                    let context = errorText.replacingOccurrences(of: "missing word", with: "").trimmingCharacters(in: .whitespaces)
                    if !context.isEmpty {
                         announcement += "Missing word '\(correction)' \(context)."
                    } else {
                         announcement += "Missing word '\(correction)'."
                    }
                } else if correction.starts(with: "extra word") {
                     // Extract context if available from the correction placeholder
                     let context = correction.replacingOccurrences(of: "extra word", with: "").trimmingCharacters(in: .whitespaces)
                     if !context.isEmpty {
                        announcement += "Extra word '\(errorText)' \(context)."
                     } else {
                        announcement += "Extra word '\(errorText)'."
                     }
                } else {
                    // Standard case: Just state the original and the correction
                    announcement += "'\(errorText)' should be '\(correction)'."
                }

            } else {
                // Fallback using the description (which might still contain the type depending on TextErrorAnalyzer)
                // Remove the prefix if found in the description as a fallback cleanup
                var desc = error.description
                if let range = desc.range(of: ": ") {
                     desc = String(desc[range.upperBound...])
                }
                announcement += desc
            }
           
            // Schedule the announcement
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                UIAccessibility.post(notification: .announcement, argument: announcement)
                print("Voice: Announced: \(announcement)")
            }
        }

        // Add a final announcement to indicate we're done
        let finalDelay = 2.0 + (Double(errors.count) * 3.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + finalDelay) {
            UIAccessibility.post(notification: .announcement, argument: "All errors have been announced.")
            print("Voice: Announced completion of error reading")
        }
    }

    
    // Method to announce the current cursor position
    private func announceCursorPosition() {
        guard let textField = self.textField,
              let selectedRange = textField.selectedTextRange else {
            return
        }
        
        // Get the cursor position
        let offset = textField.offset(from: textField.beginningOfDocument, to: selectedRange.start) + 1 // +1 for human-readable position
        let totalLength = textField.text?.count ?? 0
        
        // Get surrounding context (5 characters before and after cursor)
        var context = "Beginning of text"
        if totalLength > 0 {
            let text = textField.text ?? ""
            
            // Calculate range of characters around cursor (safely)
            let startIndex = max(0, offset - 6) // -6 instead of -5 because offset is 1-based
            let endIndex = min(totalLength, offset + 5)
            
            if startIndex < endIndex {
                // Get the surrounding text
                let beforeIndex = text.index(text.startIndex, offsetBy: startIndex)
                let afterIndex = text.index(text.startIndex, offsetBy: endIndex-1)
                context = String(text[beforeIndex...afterIndex])
                
                // Mark the cursor position
                let cursorPosition = offset - 1 - startIndex
                if cursorPosition >= 0 && cursorPosition < context.count {
                    let contextIndex = context.index(context.startIndex, offsetBy: cursorPosition)
                    let beforeCursor = context[..<contextIndex]
                    let atCursor = context[contextIndex]
                    let afterCursor = context[context.index(after: contextIndex)...]
                    context = "\(beforeCursor)【\(atCursor)】\(afterCursor)"
                }
            }
        }
        
        var announcement: String
        
        // Different announcements based on selection status
        if selectedRange.isEmpty {
            // Just a cursor position
            if totalLength == 0 {
                announcement = "Cursor at beginning of empty text field"
            } else if offset == 1 {
                announcement = "Cursor at beginning of text"
            } else if offset > totalLength {
                announcement = "Cursor at end of text"
            } else {
                announcement = "Cursor at position \(offset) of \(totalLength). Context: \(context)"
            }
        } else {
            // Text is selected
            let selectionLength = textField.offset(from: selectedRange.start, to: selectedRange.end)
            let selectionEnd = offset + selectionLength
            
            // Get selected text
            if let selectedText = textField.text(in: selectedRange) {
                announcement = "Selection from position \(offset) to \(selectionEnd) of \(totalLength). Selected text: \"\(selectedText)\""
            } else {
                announcement = "Selection from position \(offset) to \(selectionEnd) of \(totalLength)"
            }
        }
        
        // Announce the position
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
    
    // MARK: - Text Formatting
    
    // Helper enum for formatting styles
    private enum FormattingStyle {
        case bold
        case italic
        case underline
    }
    
    private func performFormatting(style: FormattingStyle) {
        guard let textField = self.textField,
              let selectedRange = textField.selectedTextRange else {
            return
        }
        
        // Get UITextRange as NSRange
        let start = textField.offset(from: textField.beginningOfDocument, to: selectedRange.start)
        let end = textField.offset(from: textField.beginningOfDocument, to: selectedRange.end)
        let nsRange = NSRange(location: start, length: end - start)
        
        // If no text is selected, announce error
        if nsRange.length == 0 {
            UIAccessibility.post(notification: .announcement, argument: "No text selected to format")
            return
        }
        
        // Get current attributed text or create a new one
        let attributedText = textField.attributedText ?? NSAttributedString(string: textField.text ?? "")
        let mutableAttributedText = NSMutableAttributedString(attributedString: attributedText)
        
        switch style {
        case .bold:
            // Bold - use a bold version of the current font
            if let currentFont = mutableAttributedText.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont {
                let boldTraits: UIFontDescriptor.SymbolicTraits = [.traitBold]
                if let boldDescriptor = currentFont.fontDescriptor.withSymbolicTraits(boldTraits) {
                    let boldFont = UIFont(descriptor: boldDescriptor, size: currentFont.pointSize)
                    mutableAttributedText.addAttribute(.font, value: boldFont, range: nsRange)
                } else {
                    let boldFont = UIFont.boldSystemFont(ofSize: currentFont.pointSize)
                    mutableAttributedText.addAttribute(.font, value: boldFont, range: nsRange)
                }
            } else {
                let boldFont = UIFont.boldSystemFont(ofSize: UIFont.systemFontSize)
                mutableAttributedText.addAttribute(.font, value: boldFont, range: nsRange)
            }
            
        case .italic:
            // Italic - use an italic version of the current font
            if let currentFont = mutableAttributedText.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont {
                let italicTraits: UIFontDescriptor.SymbolicTraits = [.traitItalic]
                if let italicDescriptor = currentFont.fontDescriptor.withSymbolicTraits(italicTraits) {
                    let italicFont = UIFont(descriptor: italicDescriptor, size: currentFont.pointSize)
                    mutableAttributedText.addAttribute(.font, value: italicFont, range: nsRange)
                } else {
                    let italicFont = UIFont.italicSystemFont(ofSize: currentFont.pointSize)
                    mutableAttributedText.addAttribute(.font, value: italicFont, range: nsRange)
                }
            } else {
                let italicFont = UIFont.italicSystemFont(ofSize: UIFont.systemFontSize)
                mutableAttributedText.addAttribute(.font, value: italicFont, range: nsRange)
            }
            
        case .underline:
            // Underline
            mutableAttributedText.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        }
        
        textField.attributedText = mutableAttributedText
    }
    
    private func performClearFormatting() {
        guard let textField = self.textField,
              let selectedRange = textField.selectedTextRange else {
            return
        }
        
        // Get UITextRange as NSRange
        let start = textField.offset(from: textField.beginningOfDocument, to: selectedRange.start)
        let end = textField.offset(from: textField.beginningOfDocument, to: selectedRange.end)
        let nsRange = NSRange(location: start, length: end - start)
        
        // If no text is selected or we can't get plain text, announce error
        if nsRange.length == 0 || textField.text == nil {
            UIAccessibility.post(notification: .announcement, argument: "No text selected to clear formatting")
            return
        }
        
        // Get the plain text of the selection
        let plainText = textField.text ?? ""
        let selectedText = (plainText as NSString).substring(with: nsRange)
        
        // Create a new attributed string with only the selected part cleared
        let attributedText = textField.attributedText ?? NSAttributedString(string: plainText)
        let mutableAttributedText = NSMutableAttributedString(attributedString: attributedText)
        
        // Replace the selected range with plain text
        let plainTextPart = NSAttributedString(string: selectedText)
        mutableAttributedText.replaceCharacters(in: nsRange, with: plainTextPart)
        
        textField.attributedText = mutableAttributedText
    }
    
    // MARK: - Helper Methods
    
    private func findWordRangeAroundCursor(in textField: UITextField) -> UITextRange? {
        guard let selectedRange = textField.selectedTextRange else { return nil }
        
        // Get word range around cursor
        let position = selectedRange.start
        return textField.tokenizer.rangeEnclosingPosition(
            position,
            with: .word,
            inDirection: UITextDirection.storage(.backward)
        )
    }
    
    private func announceVoiceOperationResult(_ operation: VoiceOperation, content: String?) {
        // Prepare accessibility announcement
        var announcement = ""
        
        switch operation {
        case .delete:
            announcement = "Deleted \(selectedGranularity)"
        case .type:
            announcement = "Typed: \(content ?? "")"
        case .insert:
            announcement = "Inserted: \(content ?? "")"
        case .space:
            announcement = "Inserted space"
        case .period:
            announcement = "Inserted period"
        case .comma:
            announcement = "Inserted comma"
        case .question:
            announcement = "Inserted question mark"
        case .exclamation:
            announcement = "Inserted exclamation mark"
        case .newline:
            announcement = "Inserted new line"
        case .read:
            announcement = "Reading text field content"
        case .unselect:
            announcement = "Selection cleared"
            case .cursorPosition:
                       // This will be handled by the announceCursorPosition method
                       announcement = ""
                   case .bold:
                       announcement = "Applied bold formatting"
                   case .italic:
                       announcement = "Applied italic formatting"
                   case .underline:
                       announcement = "Applied underline formatting"
                   case .clearFormat:
                       announcement = "Cleared formatting"
                   case .unknown:
                       announcement = "No command: \(content ?? "")"
        case .replace:
            announcement = "Replaced: \(content ?? "")"
        case .spell:
                    announcement = "Spelling selected text"
        }
                   
                   // Announce via VoiceOver if it's running
                   if UIAccessibility.isVoiceOverRunning && !announcement.isEmpty {
                       UIAccessibility.post(notification: .announcement, argument: announcement)
                   }
               }
            }

