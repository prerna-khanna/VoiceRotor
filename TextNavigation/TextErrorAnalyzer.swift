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
    // In TextErrorAnalyzer.swift
    
    func analyzeText(_ text: String, completion: @escaping ([DetectedError]) -> Void) {
        print("TextErrorAnalyzer: Starting analysis of text: \"\(text)\"")
        guard !text.isEmpty else {
            print("TextErrorAnalyzer: Text is empty, no analysis needed")
            completion([])
            return
        }
        
        // Perform local checks first - these will be our fallback
        let localSpellingErrors = checkSpelling(text)
        let localGrammarErrors = checkBasicGrammar(text)
        let localErrors = localSpellingErrors + localGrammarErrors
        
        // Helper function to limit errors
        let limitErrors = { (errors: [DetectedError]) -> [DetectedError] in
            return errors.count > 5 ? Array(errors.prefix(5)) : errors
        }
        
        // Use T5 model if available and loaded
        if let t5Inference = t5Inference, t5Inference.modelIsLoaded {
            print("TextErrorAnalyzer: Attempting correction via T5 model...")
            // Make the API call - rely on its completion handler
            t5Inference.correctText(text) { [weak self] correctedText in
                guard let self = self else {
                    // Self is nil, fallback to local checks safely on main thread
                    print("TextErrorAnalyzer: Self reference lost, falling back to local checks.")
                    DispatchQueue.main.async { completion(Array(localErrors.prefix(5))) }
                    return
                }
                
                if let correctedText = correctedText, correctedText != text {
                    // T5 provided a *different* correction
                    print("TextErrorAnalyzer: Received model correction: \"\(correctedText)\"")
                    let differences = self.findTextDifferences(original: text, corrected: correctedText)
                    
                    if !differences.isEmpty {
                        // CREATE ERROR OBJECTS FROM DIFFERENCES - REPLACE THIS WHOLE BLOCK:
                        var modelErrors: [DetectedError] = []
                        
                        // Split texts for context analysis
                        let originalWords = text.components(separatedBy: .whitespacesAndNewlines)
                        let correctedWords = correctedText.components(separatedBy: .whitespacesAndNewlines)
                        
                        for diff in differences {
                            let errorDescription: String
                            let errorType: ErrorType
                            
                            if diff.original == "missing word" {
                                errorType = .grammar // Use grammar type for missing words
                                
                                // Try to find position context
                                if let index = correctedWords.firstIndex(of: diff.corrected) {
                                    let before = index > 0 ? correctedWords[index-1] : ""
                                    let after = index < correctedWords.count-1 ? correctedWords[index+1] : ""
                                    
                                    if !before.isEmpty && !after.isEmpty {
                                        errorDescription = "Missing word: '\(diff.corrected)' between '\(before)' and '\(after)'"
                                    } else if !before.isEmpty {
                                        errorDescription = "Missing word: '\(diff.corrected)' after '\(before)'"
                                    } else if !after.isEmpty {
                                        errorDescription = "Missing word: '\(diff.corrected)' before '\(after)'"
                                    } else {
                                        errorDescription = "Missing word: '\(diff.corrected)'"
                                    }
                                } else {
                                    errorDescription = "Missing word: '\(diff.corrected)'"
                                }
                            } else if diff.corrected == "extra word" {
                                errorType = .grammar // Use grammar type for extra words
                                
                                // Try to find position context
                                if let index = originalWords.firstIndex(of: diff.original) {
                                    let before = index > 0 ? originalWords[index-1] : ""
                                    let after = index < originalWords.count-1 ? originalWords[index+1] : ""
                                    
                                    if !before.isEmpty && !after.isEmpty {
                                        errorDescription = "Extra word: '\(diff.original)' between '\(before)' and '\(after)'"
                                    } else if !before.isEmpty {
                                        errorDescription = "Extra word: '\(diff.original)' after '\(before)'"
                                    } else if !after.isEmpty {
                                        errorDescription = "Extra word: '\(diff.original)' before '\(after)'"
                                    } else {
                                        errorDescription = "Extra word: '\(diff.original)'"
                                    }
                                } else {
                                    errorDescription = "Extra word: '\(diff.original)'"
                                }
                            } else {
                                errorType = .spelling // Keep spelling type for actual misspellings
                                errorDescription = "'\(diff.original)' should be '\(diff.corrected)'"
                            }
                            
                            modelErrors.append(DetectedError(
                                type: errorType,
                                description: errorDescription,
                                errorText: diff.original,
                                correction: diff.corrected
                            ))
                        }
                        
                        print("TextErrorAnalyzer: Found \(modelErrors.count) errors using language model.")
                        // Call completion with model errors on main thread
                        DispatchQueue.main.async { completion(limitErrors(modelErrors)) }
                        
                    } else {
                        // T5 correction resulted in no identifiable differences (safety check)
                        print("TextErrorAnalyzer: Model provided correction, but no differences found. Falling back to local checks.")
                        // Call completion with local errors on main thread
                        DispatchQueue.main.async { completion(limitErrors(localErrors)) }
                    }
                } else if let correctedText = correctedText, correctedText == text {
                    // T5 returned the original text (no errors found by model)
                    print("TextErrorAnalyzer: Model found no errors (returned original text). Falling back to local checks.")
                    // Call completion with local errors on main thread
                    DispatchQueue.main.async { completion(limitErrors(localErrors)) }
                } else {
                    // T5 call failed (returned nil, timed out *within T5*, or other error)
                    print("TextErrorAnalyzer: Model correction failed or did not provide a result. Falling back to local checks.")
                    // Call completion with local errors on main thread
                    DispatchQueue.main.async { completion(limitErrors(localErrors)) }
                }
            }
        } else {
            // T5 model not available or not loaded
            print("TextErrorAnalyzer: T5 Model not available or not loaded. Using local checks.")
            // Call completion with local errors on main thread
            DispatchQueue.main.async { completion(limitErrors(localErrors)) }
        }
    }
    
    
    // Format errors into an accessibility-friendly message with punctuation pronunciation
    func formatErrorsForAccessibility(_ errors: [DetectedError]) -> String {
        guard !errors.isEmpty else {
            return "No errors detected."
        }
        
        var message = "Found \(errors.count) \(errors.count > 1 ? "errors" : "error"): "
        
        for (index, error) in errors.enumerated() {
            let errorNumber = index + 1
            
            // Simplified messaging without categorization
            if error.errorText?.starts(with: "missing word") == true {
                // Missing word case
                message += "\n\(errorNumber). Missing '\(error.correction ?? "")' \(error.errorText?.replacingOccurrences(of: "missing word ", with: "") ?? "")"
            } else if error.correction?.starts(with: "extra word") == true {
                // Extra word case
                message += "\n\(errorNumber). Extra word '\(error.errorText ?? "")' \(error.correction?.replacingOccurrences(of: "extra word ", with: "") ?? "")"
            } else {
                // Regular word correction case (spelling/grammar)
                message += "\n\(errorNumber). '\(error.errorText ?? "")' should be '\(error.correction ?? "")'"
            }
        }
        
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
                    description: " '\(misspelledWord)'" +
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
        
        // Use dynamic programming to find the alignment
        var i = 0  // original index
        var j = 0  // corrected index
        
        while i < originalWords.count && j < correctedWords.count {
            if originalWords[i] == correctedWords[j] {
                // Words match, move both indices
                i += 1
                j += 1
            } else {
                // Words don't match - check for insertion (missing word)
                if j+1 < correctedWords.count && i < originalWords.count && originalWords[i] == correctedWords[j+1] {
                    // Missing word in original text - find surrounding context
                    let beforeWord = j > 0 ? correctedWords[j-1] : ""
                    let afterWord = correctedWords[j+1]
                    
                    let contextInfo = !beforeWord.isEmpty && !afterWord.isEmpty ?
                    "between '\(beforeWord)' and '\(afterWord)'" :
                    (!beforeWord.isEmpty ? "after '\(beforeWord)'" :
                        (!afterWord.isEmpty ? "before '\(afterWord)'" : ""))
                    
                    differences.append(TextDifference(
                        original: "missing word \(contextInfo)",
                        corrected: correctedWords[j],
                        isLikelySpellingError: false
                    ))
                    j += 1  // Only advance corrected index
                } else if i+1 < originalWords.count && originalWords[i+1] == correctedWords[j] {
                    // Extra word in original
                    let beforeWord = i > 0 ? originalWords[i-1] : ""
                    let afterWord = i+1 < originalWords.count ? originalWords[i+1] : ""
                    
                    let contextInfo = !beforeWord.isEmpty && !afterWord.isEmpty ?
                    "between '\(beforeWord)' and '\(afterWord)'" :
                    (!beforeWord.isEmpty ? "after '\(beforeWord)'" :
                        (!afterWord.isEmpty ? "before '\(afterWord)'" : ""))
                    
                    differences.append(TextDifference(
                        original: originalWords[i],
                        corrected: "extra word \(contextInfo)",
                        isLikelySpellingError: false
                    ))
                    i += 1  // Only advance original index
                } else {
                    // Simple replacement
                    differences.append(TextDifference(
                        original: originalWords[i],
                        corrected: correctedWords[j],
                        isLikelySpellingError: true
                    ))
                    i += 1
                    j += 1
                }
            }
        }
        
        // Handle trailing words in either text
        while i < originalWords.count {
            let beforeWord = i > 0 ? originalWords[i-1] : ""
            differences.append(TextDifference(
                original: originalWords[i],
                corrected: "extra word after '\(beforeWord)'",
                isLikelySpellingError: false
            ))
            i += 1
        }
        
        while j < correctedWords.count {
            let beforeWord = j > 0 ? correctedWords[j-1] : ""
            differences.append(TextDifference(
                original: "missing word after '\(beforeWord)'",
                corrected: correctedWords[j],
                isLikelySpellingError: false
            ))
            j += 1
        }
        
        return differences
    }
}
