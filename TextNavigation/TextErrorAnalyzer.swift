//
//  TextErrorAnalyzer.swift
//  TextNavigation
//
//  Created by Prerna Khanna on 4/7/25.
//

import Foundation
import UIKit

enum ErrorType {
    case spelling
    case grammar
    case context
    
    var description: String {
        switch self {
        case .spelling:
            return "spelling"
        case .grammar:
            return "grammar"
        case .context:
            return "context or meaning"
        }
    }
}

struct DetectedError {
    let type: ErrorType
    let description: String
    let range: NSRange?
    let errorText: String?
    let correction: String?
    
    init(type: ErrorType, description: String, range: NSRange? = nil, errorText: String? = nil, correction: String? = nil) {
        self.type = type
        self.description = description
        self.range = range
        self.errorText = errorText
        self.correction = correction
    }
}

class TextErrorAnalyzer {
    // MARK: - Properties
    private let t5Inference: T5Inference
    private let bayesianErrorModel = BayesianErrorModel()
    
    // Use the correct URL format that worked for T5Inference
    private let contextApiUrl = "https://api-inference.huggingface.co/models/t5-small"
    private let apiKey: String
    private var isContextModelLoaded = false
    
    // MARK: - Initialization
    
    init(t5Inference: T5Inference? = nil) {
        // Use the provided T5Inference or create a new one
        self.t5Inference = t5Inference ?? T5Inference()
        
        // Get API key from Config (same as used in T5Inference)
        self.apiKey = Config.huggingFaceAPIToken
        
        print("TextErrorAnalyzer: Initialized")
        
        // Test if context model is available
        testContextModel()
    }
    
    // MARK: - Model Testing
    
    private func testContextModel() {
        print("TextErrorAnalyzer: Testing context model availability...")
        
        // Simple context analysis to test if model is available
        let testPrompt = "This is a test."
        inferenceRequest(with: "Analyze for errors in English: \(testPrompt)") { [weak self] result in
            switch result {
            case .success(_):
                print("TextErrorAnalyzer: Context model is available")
                self?.isContextModelLoaded = true
            case .failure(let error):
                print("TextErrorAnalyzer: Context model test failed: \(error.localizedDescription)")
                self?.isContextModelLoaded = false
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Analyze text for errors and return findings
    /// - Parameters:
    ///   - text: The text to analyze
    ///   - completion: Callback with array of detected errors
    func analyzeText(_ text: String, completion: @escaping ([DetectedError]) -> Void) {
        print("TextErrorAnalyzer: Starting analysis of text: \"\(text)\"")
        
        // If text is empty, return immediately
        guard !text.isEmpty else {
            print("TextErrorAnalyzer: Text is empty, no analysis needed")
            completion([])
            return
        }
        
        // Results arrays
        var spellingErrors: [DetectedError] = []
        var grammarErrors: [DetectedError] = []
        
        // STEP 1: Local spelling analysis (always works)
        print("TextErrorAnalyzer: Checking spelling with BayesianErrorModel")
        let errorProbabilities = bayesianErrorModel.analyzeText(text)
        
        for (range, probability) in errorProbabilities {
            if probability > 0.5 {  // Only include high-probability errors
                if let textRange = Range(range, in: text) {
                    let errorWord = String(text[textRange])
                    let suggestions = bayesianErrorModel.getSuggestions(for: errorWord).prefix(3)
                    let suggestionsText = suggestions.isEmpty ? "" : " (Suggestions: \(suggestions.joined(separator: ", ")))"
                    
                    spellingErrors.append(DetectedError(
                        type: .spelling,
                        description: "Spelling error: '\(errorWord)'\(suggestionsText)",
                        range: range,
                        errorText: errorWord,
                        correction: suggestions.first
                    ))
                    
                    print("TextErrorAnalyzer: Found spelling error: '\(errorWord)' with probability \(probability)")
                }
            }
        }
        
        // STEP 2: Basic local grammar checks for common errors
        print("TextErrorAnalyzer: Performing local grammar checks")
        
        // Check for "I has" error (common)
        if text.lowercased().range(of: "i has") != nil {
            let description = "Grammar error: 'I has' should be 'I have' (subject-verb agreement)"
            grammarErrors.append(DetectedError(
                type: .grammar,
                description: description,
                errorText: "I has",
                correction: "I have"
            ))
            print("TextErrorAnalyzer: Found local grammar error: 'I has'")
        }
        
        // Check for missing capitalization at the beginning of the sentence
        if let firstChar = text.first, firstChar.isLowercase,
           firstChar.isLetter, text.count > 2 {
            let errorText = String(firstChar)
            let correction = String(firstChar).uppercased()
            let description = "Grammar error: Sentence should start with capital letter"
            grammarErrors.append(DetectedError(
                type: .grammar,
                description: description,
                errorText: errorText,
                correction: correction
            ))
            print("TextErrorAnalyzer: Found capitalization error at beginning of sentence")
        }
        
        // Check for missing period at the end
        if text.count > 5 && !text.hasSuffix(".") && !text.hasSuffix("?") && !text.hasSuffix("!") {
            let description = "Grammar error: Sentence should end with punctuation"
            grammarErrors.append(DetectedError(
                type: .grammar,
                description: description,
                errorText: text,
                correction: text + "."
            ))
            print("TextErrorAnalyzer: Found missing end punctuation")
        }
        
        // STEP 3: Use T5 model for grammar if it's available (but continue if not)
        if t5Inference.modelIsLoaded {
            print("TextErrorAnalyzer: Checking grammar with T5 model")
            
            // Create task group for async operations
            let group = DispatchGroup()
            
            // Grammar check with T5
            group.enter()
            // Specifically ask for English grammar correction
            let grammarPrompt = "Fix English grammar: \(text)"
            
            // Use direct inference request to ensure English response
            inferenceRequest(with: grammarPrompt) { [weak self] result in
                defer { group.leave() }
                guard let self = self else {
                    print("TextErrorAnalyzer: Self is nil in grammar check")
                    return
                }
                
                switch result {
                case .success(let correctedText):
                    // Verify the response is English and not just echoing the prompt
                    if correctedText.hasPrefix("Fix English grammar:") || !self.isEnglishText(correctedText) {
                        print("TextErrorAnalyzer: Non-English or invalid grammar response: \"\(correctedText)\"")
                        return
                    }
                    
                    // If the corrected text is different from the original, there might be grammar issues
                    if correctedText != text {
                        print("TextErrorAnalyzer: Grammar correction available: \"\(correctedText)\"")
                        
                        // Find specific differences
                        let differences = self.findDetailedDifferences(original: text, corrected: correctedText)
                        
                        if !differences.isEmpty {
                            for diff in differences {
                                grammarErrors.append(DetectedError(
                                    type: .grammar,
                                    description: "Grammar issue: '\(diff.original)' should be '\(diff.corrected)'",
                                    errorText: diff.original,
                                    correction: diff.corrected
                                ))
                            }
                            print("TextErrorAnalyzer: Added \(differences.count) specific grammar errors")
                        } else {
                            // Fall back to general correction if specific differences can't be identified
                            grammarErrors.append(DetectedError(
                                type: .grammar,
                                description: "Grammar issue detected. Suggested correction: \"\(correctedText)\"",
                                errorText: text,
                                correction: correctedText
                            ))
                            print("TextErrorAnalyzer: Added general grammar error")
                        }
                    } else {
                        print("TextErrorAnalyzer: No grammar errors detected")
                    }
                    
                case .failure(let error):
                    print("TextErrorAnalyzer: Grammar analysis failed: \(error.localizedDescription)")
                    // Continue with local grammar checks only
                }
            }
            
            // Set a timeout for API calls
            let timeoutTask = DispatchWorkItem {
                print("TextErrorAnalyzer: Timeout reached for API calls")
                if group.wait(timeout: .now()) != .success {
                    print("TextErrorAnalyzer: Forcing completion due to timeout")
                    group.leave() // Force completion if still waiting
                }
            }
            
            // Schedule the timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0, execute: timeoutTask)
            
            // Wait for all API calls to complete or timeout
            group.notify(queue: .main) {
                // Cancel the timeout
                timeoutTask.cancel()
                
                // Combine all errors and deliver result
                self.deliverResults(spelling: spellingErrors, grammar: grammarErrors, completion: completion)
            }
        } else {
            // T5 model not available, immediately deliver local results
            print("TextErrorAnalyzer: T5 model not loaded, using only local checks")
            deliverResults(spelling: spellingErrors, grammar: grammarErrors, completion: completion)
        }
    }
    
    // Helper method to deliver results
    private func deliverResults(spelling: [DetectedError], grammar: [DetectedError], completion: @escaping ([DetectedError]) -> Void) {
        // Combine all errors
        var allErrors = spelling + grammar
        
        // Limit to most important errors if there are too many
        if allErrors.count > 5 {
            allErrors = Array(allErrors.prefix(5))
            print("TextErrorAnalyzer: Limiting to top 5 errors for clarity")
        }
        
        print("TextErrorAnalyzer: Analysis complete. Found \(allErrors.count) errors")
        completion(allErrors)
    }
    
    // Format errors into an accessibility-friendly message
    func formatErrorsForAccessibility(_ errors: [DetectedError]) -> String {
        guard !errors.isEmpty else {
            return "No errors detected."
        }
        
        // Create a more specific message that announces exactly where errors are
        var message = "Found \(errors.count) potential issue\(errors.count > 1 ? "s" : ""): "
        
        for (index, error) in errors.enumerated() {
            let errorNumber = index + 1
            
            // Include the specific error text and correction if available
            switch error.type {
            case .spelling:
                if let errorText = error.errorText, let correction = error.correction {
                    message += "\n\(errorNumber). Spelling error: '\(errorText)' should be '\(correction)'."
                } else {
                    message += "\n\(errorNumber). \(error.description)"
                }
                
            case .grammar:
                if let errorText = error.errorText, let correction = error.correction {
                    message += "\n\(errorNumber). Grammar error: '\(errorText)' should be '\(correction)'."
                } else {
                    message += "\n\(errorNumber). \(error.description)"
                }
                
            case .context:
                message += "\n\(errorNumber). \(error.description)"
            }
        }
        
        print("TextErrorAnalyzer: Formatted error message for accessibility: \"\(message)\"")
        return message
    }
    
    // MARK: - Private Methods
    
    // Check if text is likely English (not another language)
    private func isEnglishText(_ text: String) -> Bool {
        // Simple check for common English words/patterns
        let englishIndicators = ["the", "is", "are", "and", "in", "to", "for", "no", "yes",
                                "should", "error", "correct", "grammar", "spelling"]
        
        let lowercaseText = text.lowercased()
        
        // Check if the text contains any English indicators
        for indicator in englishIndicators {
            if lowercaseText.contains(indicator) {
                return true
            }
        }
        
        // Check if text contains non-Latin characters (which would suggest non-English)
        let latinCharacterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,?!-'\"()")
        let textCharacterSet = CharacterSet(charactersIn: text)
        
        // If the text contains many characters outside the Latin set, it's probably not English
        if !textCharacterSet.isSubset(of: latinCharacterSet) {
            // Convert to string and count characters to estimate non-Latin character count
            let nonLatinCharacters = text.unicodeScalars.filter { !latinCharacterSet.contains($0) }
            if nonLatinCharacters.count > 5 {
                return false
            }
        }
        
        // Default to assuming it's English if we can't determine otherwise
        return true
    }
    
    // Extract a meaningful context issue from the model's response
    private func extractContextIssue(from response: String, originalText: String) -> String {
        // If the response is just repeating the prompt or is very short, provide a default message
        if response.contains("Analyze this") || response.count < 10 {
            // Default error based on common issues
            if originalText.lowercased().contains("i has ") {
                return "Subject-verb agreement error: 'I has' should be 'I have'"
            } else if originalText.count < 10 {
                return "Text is too short to determine clear meaning"
            } else {
                return "Unclear meaning or structure"
            }
        }
        
        // Return the model's explanation, trimmed of any prompt repetition
        let cleanedResponse = response
            .replacingOccurrences(of: "Analyze this English text for logical errors.", with: "")
            .replacingOccurrences(of: "Text:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanedResponse
    }
    
    // Structure to represent differences between texts
    private struct TextDifference {
        let original: String
        let corrected: String
    }
    
    // Improved difference finding that identifies specific issues
    private func findDetailedDifferences(original: String, corrected: String) -> [TextDifference] {
        print("TextErrorAnalyzer: Finding detailed differences between original and corrected text")
        
        // Handle small, specific errors better than the previous implementation
        var differences: [TextDifference] = []
        
        // Special case for common "I has" vs "I have" error
        if original.lowercased().contains("i has ") && corrected.lowercased().contains("i have ") {
            differences.append(TextDifference(original: "I has", corrected: "I have"))
            return differences
        }
        
        // Split into words for comparison
        let originalWords = original.components(separatedBy: .whitespacesAndNewlines)
        let correctedWords = corrected.components(separatedBy: .whitespacesAndNewlines)
        
        // Check for capitalization issues
        if original.first?.isLowercase == true && corrected.first?.isUppercase == true {
            // First letter capitalization
            if let firstOriginal = originalWords.first, let firstCorrected = correctedWords.first,
               firstOriginal.lowercased() == firstCorrected.lowercased() {
                differences.append(TextDifference(
                    original: firstOriginal,
                    corrected: firstCorrected
                ))
            }
        }
        
        // Check for word-by-word differences
        let minWordCount = min(originalWords.count, correctedWords.count)
        for i in 0..<minWordCount {
            if originalWords[i].lowercased() != correctedWords[i].lowercased() {
                differences.append(TextDifference(
                    original: originalWords[i],
                    corrected: correctedWords[i]
                ))
            }
        }
        
        // Check for missing or extra words
        if originalWords.count < correctedWords.count {
            // Words added in correction
            let extraWords = correctedWords.dropFirst(originalWords.count)
            differences.append(TextDifference(
                original: "missing words",
                corrected: extraWords.joined(separator: " ")
            ))
        } else if originalWords.count > correctedWords.count {
            // Words removed in correction
            let extraWords = originalWords.dropFirst(correctedWords.count)
            differences.append(TextDifference(
                original: extraWords.joined(separator: " "),
                corrected: "should be removed"
            ))
        }
        
        // If we couldn't identify specific differences but texts differ
        if differences.isEmpty && original != corrected {
            differences.append(TextDifference(
                original: original,
                corrected: corrected
            ))
        }
        
        return differences
    }
    
    // Using the approach that worked for T5Inference
    private func inferenceRequest(with text: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: contextApiUrl) else {
            completion(.failure(NSError(domain: "TextErrorAnalyzer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5.0  // Shorter timeout to fail faster
        
        // Set headers as in the working method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Prepare payload WITHOUT language parameter that caused the error
        let payload: [String: Any] = ["inputs": text]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }
        
        // Print debug info
        print("TextErrorAnalyzer: Sending request to: \(url.absoluteString)")
        print("TextErrorAnalyzer: With payload: \(text)")
        
        // Create and start the task
        URLSession.shared.dataTask(with: request) { data, response, error in
            // Handle network error
            if let error = error {
                print("TextErrorAnalyzer: Network error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            // Check for non-success status codes
            if let httpResponse = response as? HTTPURLResponse {
                print("TextErrorAnalyzer: HTTP Status: \(httpResponse.statusCode)")
                
                // If we get a service unavailable or other error status
                if httpResponse.statusCode >= 400 {
                    let errorDescription: String
                    if httpResponse.statusCode == 503 {
                        errorDescription = "Hugging Face API service is currently unavailable (503)"
                    } else {
                        errorDescription = "HTTP error: \(httpResponse.statusCode)"
                    }
                    
                    completion(.failure(NSError(
                        domain: "TextErrorAnalyzer",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: errorDescription]
                    )))
                    return
                }
            }
            
            // Ensure we have data
            guard let data = data else {
                print("TextErrorAnalyzer: No data received")
                completion(.failure(NSError(domain: "TextErrorAnalyzer", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            // Debug: print raw response
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("TextErrorAnalyzer: Raw API response: \(rawResponse)")
                
                // Check if we got HTML instead of JSON (likely an error page)
                if rawResponse.contains("<!DOCTYPE html>") || rawResponse.contains("<html") {
                    completion(.failure(NSError(
                        domain: "TextErrorAnalyzer",
                        code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "Received HTML instead of JSON (service may be down)"]
                    )))
                    return
                }
                
                // Check for error message in JSON
                if rawResponse.contains("error") {
                    completion(.failure(NSError(
                        domain: "TextErrorAnalyzer",
                        code: -5,
                        userInfo: [NSLocalizedDescriptionKey: "API error: \(rawResponse)"]
                    )))
                    return
                }
            }
            
            // Parse the response
            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstResult = jsonResponse.first,
                   let generatedText = firstResult["generated_text"] as? String {  // Changed from translation_text to generated_text
                    print("TextErrorAnalyzer: Successfully parsed response: \(generatedText)")
                    completion(.success(generatedText))
                } else {
                    print("TextErrorAnalyzer: Invalid response format")
                    completion(.failure(NSError(domain: "TextErrorAnalyzer", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                }
            } catch {
                print("TextErrorAnalyzer: JSON parsing error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }.resume()
    }
}
