//
//  SimpleVoiceRecognitionManager.swift
//  TextNavigation
//
//  Created by Prerna Khanna on 4/3/25.
//

import Foundation
import Speech
import AVFoundation
import UIKit

// Simple operation-based voice commands
enum VoiceOperation: String {
    case type = "type"
    case delete = "delete"
    case insert = "insert"
    case unknown
    
    // Parse from recognized text
    static func from(_ text: String) -> (operation: VoiceOperation, content: String?) {
        let lowerText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for command patterns
        if lowerText == "delete" {
            return (.delete, nil)
        }
        
        if lowerText.hasPrefix("type ") {
            let content = String(lowerText.dropFirst("type ".count))
            return (.type, content)
        }
        
        if lowerText.hasPrefix("insert ") {
            let content = String(lowerText.dropFirst("insert ".count))
            return (.insert, content)
        }
        
        // Default is to just type the content
        return (.unknown, lowerText)
    }
}

class SimpleVoiceRecognitionManager: NSObject {
    // MARK: - Properties
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var isListening = false
    private weak var textField: UITextField?
    private var selectedGranularity: Granularity = .character
    
    // MARK: - Setup
    
    init(textField: UITextField?) {
        self.textField = textField
        super.init()
        
        // Request authorization on init
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
        
        // Configure for partial results
        recognitionRequest.shouldReportPartialResults = true
        
        // Setup audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Track the last valid partial result
        var lastValidPartialResult: String = ""
        
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
                                             (error as NSError).code == 1
                    
                    if !isCancellationError {
                        print("Voice: Recognition error: \(error.localizedDescription)")
                        
                        // Notify error
                        NotificationCenter.default.post(
                            name: NSNotification.Name("VoiceRecognitionError"),
                            object: nil,
                            userInfo: ["error": error.localizedDescription]
                        )
                    } else {
                        print("Voice: Recognition stopped normally")
                    }
                    return
                }
                
                if let result = result {
                    let recognizedText = result.bestTranscription.formattedString
                    print("Voice: Partial recognition: '\(recognizedText)'")
                    
                    // Store non-empty partial results
                    if !recognizedText.isEmpty {
                        lastValidPartialResult = recognizedText
                    }
                    
                    // Process final result or use last valid partial if final is empty
                    if result.isFinal {
                        print("Voice: FINAL RESULT: '\(recognizedText)'")
                        
                        // Use the last valid partial result if final is empty
                        let textToProcess = recognizedText.isEmpty ? lastValidPartialResult : recognizedText
                        
                        if !textToProcess.isEmpty {
                            print("Voice: Processing command: '\(textToProcess)'")
                            self.processRecognizedText(textToProcess)
                            
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
        // Parse the voice operation
        let (operation, content) = VoiceOperation.from(text)
        
        // Process based on operation type
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let textField = self.textField else { return }
            
            // Make sure text field is active
            if !textField.isFirstResponder {
                textField.becomeFirstResponder()
            }
            
            switch operation {
            case .delete:
                self.performDelete(granularity: self.selectedGranularity)
                
            case .type:
                if let content = content {
                    self.performType(content)
                }
                
            case .insert:
                if let content = content {
                    self.performInsert(content)
                }
                
            case .unknown:
                // For unknown commands, insert the raw text
                if let content = content {
                    self.performType(content)
                }
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
            if let text = textField.text {
                textField.text = ""
            }
        }
    }
    
    private func performType(_ text: String) {
        guard let textField = self.textField else { return }
        
        // For type command, replace entire content
        textField.text = text
        
        // Move cursor to end
        let endPosition = textField.endOfDocument
        textField.selectedTextRange = textField.textRange(from: endPosition, to: endPosition)
    }
    
    private func performInsert(_ text: String) {
        guard let textField = self.textField,
              let selectedRange = textField.selectedTextRange else {
            return
        }
        
        // Insert at current position
        textField.replace(selectedRange, withText: text)
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
        case .unknown:
            announcement = content ?? ""
        }
        
        // Announce via VoiceOver if it's running
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }
}
