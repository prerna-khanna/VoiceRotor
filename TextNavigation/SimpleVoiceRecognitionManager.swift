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

// Enhanced operation-based voice commands
enum VoiceOperation: String {
    case type = "type"
    case delete = "delete"
    case insert = "insert"
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
        
        if lowerText == "comma" {
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
        
        // Commands with content
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
    
    // Private variables
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
                    self.performInsert(content)
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
                // For unknown commands, if text is selected, do nothing
                // If no text is selected, treat as "type" and append text
                if !hasSelection && content != nil && !content!.isEmpty {
                    self.performAppend(content!)
                } else if hasSelection {
                    // Announce that command is not recognized
                    UIAccessibility.post(notification: .announcement,
                                        argument: "Command not recognized. Try delete, type, insert, bold, italic, or underline")
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
    
    // Method to read the entire text field
    private func readTextField() {
        guard let textField = self.textField else {
            return
        }
        
        let text = textField.text ?? ""
        
        if text.isEmpty {
            // If the text field is empty, announce that
            UIAccessibility.post(notification: .announcement, argument: "Text field is empty")
        } else {
            // Announce the entire text
            UIAccessibility.post(notification: .announcement, argument: text)
            
            // Highlight the text visually as well
            let allTextRange = textField.textRange(from: textField.beginningOfDocument, to: textField.endOfDocument)
            textField.selectedTextRange = allTextRange
            
            // Add a slight delay before deselecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self, weak textField] in
                // Reset selection to cursor at the end to avoid interfering with future commands
                if let textField = textField {
                    let endPosition = textField.endOfDocument
                    textField.selectedTextRange = textField.textRange(from: endPosition, to: endPosition)
                }
            }
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
        }
        
        // Announce via VoiceOver if it's running
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }
}
