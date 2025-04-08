//
//  TextErrorAnalyzer.swift
//  TextNavigation
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
    private let t5Inference: T5Inference?
    private let spellChecker = UITextChecker()
    
    // Custom dictionary for common misspellings
    private let customCorrections: [String: String] = [
        "droping": "dropping",
        "degres": "degrees",
        "wether": "weather",
        "cloths": "clothes",
        "posibility": "possibility",
        "precipation": "precipitation",
        "bringign": "bringing",
        "waering": "wearing",
        "cancled": "canceled",
        "unfavorble": "unfavorable",
        "condtions": "conditions",
        "reccomend": "recommend",
        "umbella": "umbrella",
        "forcast": "forecast",
        "wekend": "weekend",
        "tempratures": "temperatures"
    ]
    
    // MARK: - Initialization
    
    init(t5Inference: T5Inference? = nil) {
        self.t5Inference = t5Inference
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
        var errors: [DetectedError] = []
        
        // STEP 1: Perform basic spelling checks using UITextChecker as a fallback
        let localSpellingErrors = checkSpelling(text)
        
        // STEP 2: Add basic grammar checks (these always run locally)
        let localGrammarErrors = checkBasicGrammar(text)
        
        // STEP 3: Use T5 model for comprehensive correction if available
        if let t5Inference = t5Inference, t5Inference.modelIsLoaded {
            // Create a dispatch group to coordinate API calls
            let group = DispatchGroup()
            
            // Variable to store model errors
            var modelErrors: [DetectedError] = []
            
            // Enter the group for the API call
            group.enter()
            
            // Use the model for both spelling and grammar correction
            t5Inference.correctText(text) { [weak self] correctedText in
                defer { group.leave() }
                guard let self = self, let correctedText = correctedText, correctedText != text else { return }
                
                print("TextErrorAnalyzer: Received model correction: \"\(correctedText)\"")
                
                // Find the differences between original and corrected text
                let differences = self.findTextDifferences(original: text, corrected: correctedText)
                
                // Add each difference as an error
                for diff in differences {
                    let errorType: ErrorType = diff.isLikelySpellingError ? .spelling : .grammar
                    modelErrors.append(DetectedError(
                        type: errorType,
                        description: "\(errorType.description.capitalized) error: '\(diff.original)' should be '\(diff.corrected)'",
                        errorText: diff.original,
                        correction: diff.corrected
                    ))
                }
                
                print("TextErrorAnalyzer: Found \(differences.count) errors using language model")
            }
            
            // Wait for API call with timeout (3 seconds)
            let waitResult = group.wait(timeout: .now() + 3.0)
            
            if waitResult == .success && !modelErrors.isEmpty {
                // Use model errors if available
                errors = modelErrors
                print("TextErrorAnalyzer: Using \(modelErrors.count) errors from language model")
            } else {
                // Fall back to local errors if model failed or timed out
                errors = localSpellingErrors + localGrammarErrors
                if waitResult == .timedOut {
                    print("TextErrorAnalyzer: T5 inference timed out, using local checks")
                } else {
                    print("TextErrorAnalyzer: T5 model returned no errors, using local checks")
                }
            }
        } else {
            // Use local checks if model isn't available
            errors = localSpellingErrors + localGrammarErrors
            print("TextErrorAnalyzer: T5 model not available, using local checks only")
        }
        
        // Limit to most important errors if there are too many
        if errors.count > 5 {
            errors = Array(errors.prefix(5))
            print("TextErrorAnalyzer: Limiting to top 5 errors for clarity")
        }
        
        print("TextErrorAnalyzer: Analysis complete. Found \(errors.count) errors")
        completion(errors)
    }
    
    // Format errors into an accessibility-friendly message with punctuation pronunciation
    func formatErrorsForAccessibility(_ errors: [DetectedError]) -> String {
        guard !errors.isEmpty else {
            return "No errors detected."
        }
        
        // Create a more specific message that announces exactly where errors are
        var message = "Found \(errors.count) potential \(errors.count > 1 ? "issues" : "issue"): "
        
        for (index, error) in errors.enumerated() {
            let errorNumber = index + 1
            
            // Include the specific error text and correction if available
            switch error.type {
            case .spelling, .grammar:
                if let errorText = error.errorText, let correction = error.correction {
                    // Add explicit pronunciation of punctuation in the correction
                    let pronounceableCorrection = addPronounceablePunctuation(correction)
                    message += "\n\(errorNumber). \(error.type.description.capitalized) error: '\(errorText)' should be '\(pronounceableCorrection)'."
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
    
    /// Check for spelling errors using UITextChecker and custom dictionary
    private func checkSpelling(_ text: String) -> [DetectedError] {
        var errors: [DetectedError] = []
        
        // Create a range for the entire text
        let range = NSRange(location: 0, length: (text as NSString).length)
        
        // Initialize variables for the loop
        var searchRange = range
        var misspelledRange = NSRange(location: NSNotFound, length: 0)
        
        // Check for multiple misspellings
        repeat {
            // Find the next misspelled word
            misspelledRange = spellChecker.rangeOfMisspelledWord(
                in: text,
                range: searchRange,
                startingAt: searchRange.location,
                wrap: false,
                language: "en")
            
            // If we found a misspelling
            if misspelledRange.location != NSNotFound {
                // Get the misspelled word
                let misspelledWord = (text as NSString).substring(with: misspelledRange)
                
                // Check custom dictionary first
                var correction: String?
                if let customCorrection = customCorrections[misspelledWord.lowercased()] {
                    correction = customCorrection
                } else {
                    // Get spelling suggestions from system
                    let suggestions = spellChecker.guesses(
                        forWordRange: misspelledRange,
                        in: text,
                        language: "en") ?? []
                    correction = suggestions.first
                }
                
                // Create error object
                let error = DetectedError(
                    type: .spelling,
                    description: "Spelling error: '\(misspelledWord)'" +
                        (correction != nil ? " (Suggestion: \(correction!))" : ""),
                    range: misspelledRange,
                    errorText: misspelledWord,
                    correction: correction
                )
                
                errors.append(error)
                print("TextErrorAnalyzer: Found spelling error: '\(misspelledWord)'")
                
                // Update search range to continue after this misspelling
                searchRange = NSRange(
                    location: misspelledRange.location + misspelledRange.length,
                    length: range.length - (misspelledRange.location + misspelledRange.length)
                )
            }
        } while misspelledRange.location != NSNotFound && searchRange.length > 0
        
        return errors
    }
    
    /// Check for basic grammar errors without API
    private func checkBasicGrammar(_ text: String) -> [DetectedError] {
        var errors: [DetectedError] = []
        
        // Check for "I has" error (common)
        if text.lowercased().range(of: "i has") != nil {
            let description = "Grammar error: 'I has' should be 'I have' (subject-verb agreement)"
            errors.append(DetectedError(
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
            errors.append(DetectedError(
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
            errors.append(DetectedError(
                type: .grammar,
                description: description,
                errorText: text,
                correction: text + "."
            ))
            print("TextErrorAnalyzer: Found missing end punctuation")
        }
        
        // Check for double punctuation
        if text.contains("..") || text.contains(",,") || text.contains("!.") || text.contains("?.") {
            let description = "Grammar error: Double punctuation should be avoided"
            errors.append(DetectedError(
                type: .grammar,
                description: description,
                errorText: "double punctuation",
                correction: "single punctuation"
            ))
            print("TextErrorAnalyzer: Found double punctuation")
        }
        
        return errors
    }
    
    // Add pronounceable punctuation for accessibility
    private func addPronounceablePunctuation(_ text: String) -> String {
        var result = text
        
        // Replace punctuation with spoken versions
        result = result.replacingOccurrences(of: ".", with: " period")
        result = result.replacingOccurrences(of: ",", with: " comma")
        result = result.replacingOccurrences(of: "?", with: " question mark")
        result = result.replacingOccurrences(of: "!", with: " exclamation point")
        result = result.replacingOccurrences(of: ":", with: " colon")
        result = result.replacingOccurrences(of: ";", with: " semicolon")
        result = result.replacingOccurrences(of: "-", with: " dash")
        result = result.replacingOccurrences(of: "(", with: " open parenthesis")
        result = result.replacingOccurrences(of: ")", with: " close parenthesis")
        result = result.replacingOccurrences(of: "'", with: " apostrophe")
        result = result.replacingOccurrences(of: "\"", with: " quote")
        
        return result
    }
    
    // Structure to represent differences between texts
    private struct TextDifference {
        let original: String
        let corrected: String
        let isLikelySpellingError: Bool
    }
    
    // Find differences between original and corrected text
    private func findTextDifferences(original: String, corrected: String) -> [TextDifference] {
        var differences: [TextDifference] = []
        
        // Split into words for comparison
        let originalWords = original.components(separatedBy: .whitespacesAndNewlines)
        let correctedWords = corrected.components(separatedBy: .whitespacesAndNewlines)
        
        // Compare word by word where possible
        let minWords = min(originalWords.count, correctedWords.count)
        
        for i in 0..<minWords {
            let origWord = originalWords[i]
            let corrWord = correctedWords[i]
            
            if origWord != corrWord {
                // Calculate edit distance to determine if it's likely a spelling error
                let distance = calculateEditDistance(origWord.lowercased(), corrWord.lowercased())
                let maxLength = max(origWord.count, corrWord.count)
                
                // If edit distance is small relative to word length, likely spelling error
                // otherwise it's probably a grammar error
                let isSpellingError = Double(distance) / Double(maxLength) < 0.5
                
                differences.append(TextDifference(
                    original: origWord,
                    corrected: corrWord,
                    isLikelySpellingError: isSpellingError
                ))
            }
        }
        
        // If the texts are different lengths, add extra words as differences
        if originalWords.count < correctedWords.count {
            // Words added in correction
            for i in minWords..<correctedWords.count {
                differences.append(TextDifference(
                    original: "(missing)",
                    corrected: correctedWords[i],
                    isLikelySpellingError: false
                ))
            }
        } else if originalWords.count > correctedWords.count {
            // Words removed in correction
            for i in minWords..<originalWords.count {
                differences.append(TextDifference(
                    original: originalWords[i],
                    corrected: "(should be removed)",
                    isLikelySpellingError: false
                ))
            }
        }
        
        // If we didn't find any specific differences but texts are different
        if differences.isEmpty && original != corrected {
            // Fall back to treating the entire text as one difference
            differences.append(TextDifference(
                original: original,
                corrected: corrected,
                isLikelySpellingError: false
            ))
        }
        
        return differences
    }
    
    // Calculate Levenshtein edit distance between two strings
    private func calculateEditDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)
        let m = s1.count
        let n = s2.count
        
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        // Initialize first row and column
        for i in 0...m {
            dp[i][0] = i
        }
        
        for j in 0...n {
            dp[0][j] = j
        }
        
        // Fill the matrix
        for i in 1...m {
            for j in 1...n {
                if s1[i-1] == s2[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1]) + 1
                }
            }
        }
        
        return dp[m][n]
    }
}
