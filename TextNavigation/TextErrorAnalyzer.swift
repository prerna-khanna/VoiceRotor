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
    
    init(type: ErrorType, description: String, range: NSRange? = nil) {
        self.type = type
        self.description = description
        self.range = range
    }
}

class TextErrorAnalyzer {
    // MARK: - Properties
    private let t5Inference: T5Inference
    private let bayesianErrorModel = BayesianErrorModel()
    
    // Use the correct URL format that worked for T5Inference
    private let contextApiUrl = "https://api-inference.huggingface.co/models/google-t5/t5-small"
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
        inferenceRequest(with: "Analyze for errors: \(testPrompt)") { [weak self] result in
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
        
        // Create a task group to run multiple analyses in parallel
        let group = DispatchGroup()
        
        // Results arrays
        var spellingErrors: [DetectedError] = []
        var grammarErrors: [DetectedError] = []
        var contextErrors: [DetectedError] = []
        
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
                        description: "Possible spelling error in '\(errorWord)'\(suggestionsText)",
                        range: range
                    ))
                    
                    print("TextErrorAnalyzer: Found spelling error: '\(errorWord)' with probability \(probability)")
                }
            }
        }
        
        // STEP 2: Check for grammar errors using T5 model
        if t5Inference.modelIsLoaded {
            print("TextErrorAnalyzer: Checking grammar with T5 model")
            group.enter()
            t5Inference.correctSentence(text) { [weak self] correctedText in
                defer { group.leave() }
                guard let self = self, let correctedText = correctedText else {
                    print("TextErrorAnalyzer: No grammar correction available")
                    return
                }
                
                // If the corrected text is different from the original, there might be grammar issues
                if correctedText != text {
                    print("TextErrorAnalyzer: Grammar correction available: \"\(correctedText)\"")
                    
                    // Calculate basic diff to identify what changed
                    let differences = self.findDifferences(original: text, corrected: correctedText)
                    if differences.isEmpty {
                        grammarErrors.append(DetectedError(
                            type: .grammar,
                            description: "Grammar issues detected. Suggested correction: \"\(correctedText)\""
                        ))
                    } else {
                        for diff in differences {
                            grammarErrors.append(DetectedError(
                                type: .grammar,
                                description: diff
                            ))
                        }
                    }
                    
                    print("TextErrorAnalyzer: Added \(grammarErrors.count) grammar error(s)")
                } else {
                    print("TextErrorAnalyzer: No grammar errors detected by T5")
                }
            }
        } else {
            print("TextErrorAnalyzer: T5 model not loaded, skipping grammar check")
        }
        
        // STEP 3: Check for context/semantic errors using the approach that worked
        if isContextModelLoaded {
            print("TextErrorAnalyzer: Checking context with T5 model")
            group.enter()
            
            // Prepare a context analysis prompt
            let contextPrompt = "Analyze this text for contextual or logical errors. If there are no issues, just say 'No issues'. Text: \"\(text)\""
            
            inferenceRequest(with: contextPrompt) { result in
                defer { group.leave() }
                
                switch result {
                case .success(let analysisResult):
                    print("TextErrorAnalyzer: Context analysis result: \"\(analysisResult)\"")
                    
                    if !analysisResult.lowercased().contains("no issue") &&
                       !analysisResult.lowercased().contains("none") &&
                       !analysisResult.lowercased().contains("clear and coherent") {
                        contextErrors.append(DetectedError(
                            type: .context,
                            description: "Potential context issue: \(analysisResult)"
                        ))
                        print("TextErrorAnalyzer: Added context error")
                    } else {
                        print("TextErrorAnalyzer: No context errors detected")
                    }
                case .failure(let error):
                    print("TextErrorAnalyzer: Context analysis failed: \(error.localizedDescription)")
                }
            }
        } else {
            print("TextErrorAnalyzer: Context model not loaded, skipping context check")
        }
        
        // Set a timeout for API calls
        let timeoutTask = DispatchWorkItem {
            print("TextErrorAnalyzer: Timeout reached, checking if group is complete...")
            // No action needed - the group.notify will handle completion
        }
        
        // Schedule the timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + 10.0, execute: timeoutTask)
        
        // Wait for all API calls to complete
        group.notify(queue: .main) {
            // Cancel the timeout
            timeoutTask.cancel()
            
            // Combine all errors
            var allErrors = spellingErrors + grammarErrors + contextErrors
            
            // Limit to most important errors if there are too many
            if allErrors.count > 5 {
                allErrors = Array(allErrors.prefix(5))
                print("TextErrorAnalyzer: Limiting to top 5 errors for clarity")
            }
            
            print("TextErrorAnalyzer: Analysis complete. Found \(allErrors.count) errors")
            completion(allErrors)
        }
    }
    
    // Format errors into an accessibility-friendly message
    func formatErrorsForAccessibility(_ errors: [DetectedError]) -> String {
        guard !errors.isEmpty else {
            return "No errors detected."
        }
        
        let errorsByType = Dictionary(grouping: errors, by: { $0.type })
        var message = "Found \(errors.count) potential issues: "
        
        for (type, errorsOfType) in errorsByType {
            message += "\n\(errorsOfType.count) \(type.description) issue\(errorsOfType.count > 1 ? "s" : ""): "
            for error in errorsOfType {
                message += "\n- \(error.description)"
            }
        }
        
        print("TextErrorAnalyzer: Formatted error message for accessibility: \"\(message)\"")
        return message
    }
    
    // MARK: - Private Methods
    
    private func findDifferences(original: String, corrected: String) -> [String] {
        print("TextErrorAnalyzer: Finding differences between original and corrected text")
        
        // Split into words for basic comparison
        let originalWords = original.components(separatedBy: .whitespacesAndNewlines)
        let correctedWords = corrected.components(separatedBy: .whitespacesAndNewlines)
        
        var differences: [String] = []
        
        // Simple word-by-word comparison
        if originalWords.count == correctedWords.count {
            for i in 0..<originalWords.count {
                if originalWords[i] != correctedWords[i] {
                    differences.append("'\(originalWords[i])' should be '\(correctedWords[i])'")
                }
            }
        } else {
            // If word counts differ, just add a general difference note
            differences.append("Text structure needs correction")
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
        request.timeoutInterval = 30.0
        
        // Set headers as in the working method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Prepare payload
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
            
            // Log HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                print("TextErrorAnalyzer: HTTP Status: \(httpResponse.statusCode)")
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
            }
            
            // Parse the response
            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstResult = jsonResponse.first,
                   let generatedText = firstResult["translation_text"] as? String {  // Change here too
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
