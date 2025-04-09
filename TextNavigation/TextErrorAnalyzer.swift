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
    
    // MARK: - Initialization
    
    init(t5Inference: T5Inference? = nil) {
        self.t5Inference = t5Inference
        print("TextErrorAnalyzer: Initialized with Grammarly model")
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
        
        // STEP 1: Try the T5/Grammarly model first if available
        if let t5Inference = t5Inference, t5Inference.modelIsLoaded {
            // Create a dispatch group for synchronized API calls
            let group = DispatchGroup()
            var modelErrors: [DetectedError] = []
            
            // Enter the group
            group.enter()
            
            // Use the Grammarly model for correction
            t5Inference.correctText(text) { [weak self] correctedText in
                defer { group.leave() }
                guard let self = self else { return }
                
                if let correctedText = correctedText, correctedText != text {
                    print("TextErrorAnalyzer: Received model correction: \"\(correctedText)\"")
                    
                    // Find all differences between original and corrected text
                    let differences = self.findTextDifferences(original: text, corrected: correctedText)
                    print("TextErrorAnalyzer: Found \(differences.count) differences between original and corrected text")
                    
                    // Convert differences to errors
                    for diff in differences {
                        modelErrors.append(DetectedError(
                            type: diff.type,
                            description: "\(diff.type.description.capitalized) error: '\(diff.original)' should be '\(diff.corrected)'.",
                            errorText: diff.original,
                            correction: diff.corrected
                        ))
                    }
                } else {
                    print("TextErrorAnalyzer: Model found no corrections needed or returned nil")
                }
            }
            
            // Wait for a maximum of 3 seconds for the model to respond
            let waitResult = group.wait(timeout: .now() + 3.0)
            
            // If the model provided errors and didn't time out, use those
            if waitResult == .success && !modelErrors.isEmpty {
                // Remove duplicates (same error text, different descriptions)
                let uniqueErrors = self.removeDuplicateErrors(modelErrors)
                print("TextErrorAnalyzer: Using \(uniqueErrors.count) errors from Grammarly model")
                completion(uniqueErrors)
                return
            } else {
                if waitResult == .timedOut {
                    print("TextErrorAnalyzer: Grammarly model timed out, falling back to local checks")
                } else {
                    print("TextErrorAnalyzer: Grammarly model provided no errors, falling back to local checks")
                }
                // Fall back to local checks
                let localErrors = performLocalChecks(text)
                completion(localErrors)
                return
            }
        } else {
            // If model isn't available, use local checks
            print("TextErrorAnalyzer: Grammarly model not available, using local checks")
            let localErrors = performLocalChecks(text)
            completion(localErrors)
            return
        }
    }
    
    // Format errors into an accessibility-friendly message with punctuation pronunciation
    func formatErrorsForAccessibility(_ errors: [DetectedError]) -> String {
        guard !errors.isEmpty else {
            return "No errors detected."
        }
        
        // Create a specific message that announces exactly where errors are
        var message = "Found \(errors.count) potential \(errors.count > 1 ? "issues" : "issue"): "
        
        for (index, error) in errors.enumerated() {
            let errorNumber = index + 1
            
            // Include the specific error text and correction if available
            switch error.type {
            case .spelling, .grammar:
                if let errorText = error.errorText, let correction = error.correction {
                    message += "\n\(errorNumber). \(error.type.description.capitalized) error: '\(errorText)' should be '\(correction)'."
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
    
    // Remove duplicate errors (same error text with different descriptions)
    private func removeDuplicateErrors(_ errors: [DetectedError]) -> [DetectedError] {
        var uniqueErrors: [DetectedError] = []
        var seenErrorTexts: Set<String> = []
        
        for error in errors {
            if let errorText = error.errorText {
                let normalizedText = errorText.lowercased()
                if !seenErrorTexts.contains(normalizedText) {
                    uniqueErrors.append(error)
                    seenErrorTexts.insert(normalizedText)
                }
            } else {
                // Always include errors without specific error text
                uniqueErrors.append(error)
            }
        }
        
        return uniqueErrors
    }
    
    // Perform local checks for common errors
    private func performLocalChecks(_ text: String) -> [DetectedError] {
        var errors: [DetectedError] = []
        
        // Check for missing capitalization at the beginning
        if let firstChar = text.first, firstChar.isLowercase, firstChar.isLetter {
            let upper = String(firstChar).uppercased()
            errors.append(DetectedError(
                type: .grammar,
                description: "Grammar error: Sentence should start with a capital letter",
                errorText: String(firstChar),
                correction: upper
            ))
            print("TextErrorAnalyzer: Found capitalization error at beginning of sentence")
        }
        
        // Check for missing ending punctuation
        if text.count > 3 && !text.hasSuffix(".") && !text.hasSuffix("!") && !text.hasSuffix("?") {
            errors.append(DetectedError(
                type: .grammar,
                description: "Grammar error: Sentence should end with punctuation",
                errorText: text,
                correction: text + "."
            ))
            print("TextErrorAnalyzer: Found missing end punctuation")
        }
        
        // Check for standard spelling errors using UITextChecker
        let range = NSRange(location: 0, length: (text as NSString).length)
        var searchRange = range
        var misspelledRange = NSRange(location: NSNotFound, length: 0)
        
        // Look for misspelled words
        repeat {
            misspelledRange = spellChecker.rangeOfMisspelledWord(
                in: text,
                range: searchRange,
                startingAt: searchRange.location,
                wrap: false,
                language: "en")
            
            if misspelledRange.location != NSNotFound {
                let misspelledWord = (text as NSString).substring(with: misspelledRange)
                
                // Get suggestions
                let suggestions = spellChecker.guesses(
                    forWordRange: misspelledRange,
                    in: text,
                    language: "en") ?? []
                
                // Add error if we have a suggestion
                if !suggestions.isEmpty {
                    errors.append(DetectedError(
                        type: .spelling,
                        description: "Spelling error: '\(misspelledWord)' should be '\(suggestions[0])'",
                        range: misspelledRange,
                        errorText: misspelledWord,
                        correction: suggestions[0]
                    ))
                    print("TextErrorAnalyzer: Found spelling error: '\(misspelledWord)'")
                }
                
                // Update search range
                searchRange = NSRange(
                    location: misspelledRange.location + misspelledRange.length,
                    length: range.length - (misspelledRange.location + misspelledRange.length)
                )
            }
        } while misspelledRange.location != NSNotFound && searchRange.length > 0
        
        // Check for capitalization of proper names
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        for word in words {
            if word.count > 1 && word.first?.isLowercase == true {
                // Check if this word should be capitalized (if capitalized version is not flagged as misspelled)
                let capitalizedWord = word.prefix(1).uppercased() + word.dropFirst()
                let wordRange = NSRange(location: 0, length: capitalizedWord.utf16.count)
                
                let isMisspelled = spellChecker.rangeOfMisspelledWord(
                    in: capitalizedWord,
                    range: wordRange,
                    startingAt: 0,
                    wrap: false,
                    language: "en").location != NSNotFound
                
                // If the capitalized version is NOT misspelled, it's probably a proper noun
                if !isMisspelled {
                    // Find this word in the original text
                    if let range = text.range(of: word) {
                        let nsRange = NSRange(range, in: text)
                        errors.append(DetectedError(
                            type: .spelling,
                            description: "Spelling error: '\(word)' should be '\(capitalizedWord)'",
                            range: nsRange,
                            errorText: word,
                            correction: capitalizedWord
                        ))
                        print("TextErrorAnalyzer: Found proper noun capitalization error: '\(word)'")
                    }
                }
            }
        }
        
        // Limit to 5 errors max
        if errors.count > 5 {
            errors = Array(errors.prefix(5))
            print("TextErrorAnalyzer: Limiting to top 5 errors for clarity")
        }
        
        print("TextErrorAnalyzer: Analysis complete. Found \(errors.count) errors")
        return errors
    }
    
    // Structure to represent differences between texts
    private struct TextDifference {
        let original: String
        let corrected: String
        let type: ErrorType
    }
    
    // Find detailed differences between original and corrected text
    private func findTextDifferences(original: String, corrected: String) -> [TextDifference] {
        var differences: [TextDifference] = []
        
        // Break down to sentences first
        let originalSentences = original.components(separatedBy: [".","!","?"])
        let correctedSentences = corrected.components(separatedBy: [".","!","?"])
        
        // If sentence count differs dramatically, just use word-by-word comparison
        if abs(originalSentences.count - correctedSentences.count) > 2 {
            return findWordDifferences(original: original, corrected: corrected)
        }
        
        // Compare each sentence
        let sentenceCount = min(originalSentences.count, correctedSentences.count)
        for i in 0..<sentenceCount {
            let origSentence = originalSentences[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let corrSentence = correctedSentences[i].trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty sentences
            if origSentence.isEmpty || corrSentence.isEmpty {
                continue
            }
            
            // If sentences are different, find word-level differences
            if origSentence != corrSentence {
                let sentenceDiffs = findWordDifferences(original: origSentence, corrected: corrSentence)
                differences.append(contentsOf: sentenceDiffs)
            }
        }
        
        // If we didn't find any specific differences but texts differ
        if differences.isEmpty && original != corrected {
            // Check for missing punctuation
            if corrected.hasSuffix(".") && !original.hasSuffix(".") {
                differences.append(TextDifference(
                    original: original,
                    corrected: original + ".",
                    type: .grammar
                ))
            } else {
                // Use the whole text as one difference
                differences.append(TextDifference(
                    original: original,
                    corrected: corrected,
                    type: .grammar
                ))
            }
        }
        
        return differences
    }
    
    // Find word-level differences between texts
    private func findWordDifferences(original: String, corrected: String) -> [TextDifference] {
        var differences: [TextDifference] = []
        
        // Split into words
        let origWords = original.components(separatedBy: .whitespacesAndNewlines)
        let corrWords = corrected.components(separatedBy: .whitespacesAndNewlines)
        
        // Compare word by word
        let wordCount = min(origWords.count, corrWords.count)
        for i in 0..<wordCount {
            if origWords[i] != corrWords[i] {
                // Determine if it's a spelling or grammar issue
                let type: ErrorType
                
                // If words are similar (just case or close edit distance), it's likely spelling
                if origWords[i].lowercased() == corrWords[i].lowercased() {
                    type = .grammar // Capitalization is grammar
                } else {
                    // Calculate edit distance to check if it's a minor spelling correction
                    let distance = calculateEditDistance(origWords[i], corrWords[i])
                    let maxLength = max(origWords[i].count, corrWords[i].count)
                    
                    // If edit distance is small relative to word length, it's spelling
                    type = (distance <= 2 || Double(distance) / Double(maxLength) < 0.5) ? .spelling : .grammar
                }
                
                differences.append(TextDifference(
                    original: origWords[i],
                    corrected: corrWords[i],
                    type: type
                ))
            }
        }
        
        // Check for extra or missing words
        if origWords.count < corrWords.count {
            // Extra words in correction
            for i in wordCount..<corrWords.count {
                differences.append(TextDifference(
                    original: "(missing)",
                    corrected: corrWords[i],
                    type: .grammar
                ))
            }
        } else if origWords.count > corrWords.count {
            // Missing words in correction
            for i in wordCount..<origWords.count {
                differences.append(TextDifference(
                    original: origWords[i],
                    corrected: "(should be removed)",
                    type: .grammar
                ))
            }
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
