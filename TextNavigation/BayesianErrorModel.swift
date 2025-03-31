import Foundation
import UIKit

class BayesianErrorModel {
    // MARK: - Properties
    private let spellChecker = UITextChecker()
    private var userCorrectionHistory: [String: String] = [:] // Track user corrections
    
    // MARK: - Public Methods
    
    /// Analyze text and return error probabilities for each word
    /// - Parameter text: The text to analyze
    /// - Returns: Dictionary mapping ranges to error probabilities (0.0-1.0)
    func analyzeText(_ text: String) -> [NSRange: Double] {
        var errorProbabilities = [NSRange: Double]()
        guard !text.isEmpty else { return errorProbabilities }
        
        // Split the text into words and analyze each one
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        var currentIndex = 0
        
        for word in words {
            guard !word.isEmpty else {
                currentIndex += 1
                continue
            }
            
            // Create a range for this word
            let location = text.distance(from: text.startIndex, to: text.index(text.startIndex, offsetBy: currentIndex))
            let range = NSRange(location: location, length: word.count)
            
            // Calculate error probability
            let probability = checkSpellingError(word)
            if probability > 0 {
                errorProbabilities[range] = probability
            }
            
            // Move to the next word position (word length + 1 for space)
            currentIndex += word.count + 1
        }
        
        return errorProbabilities
    }
    
    /// Get suggestions for a potentially misspelled word
    /// - Parameter word: The word to check
    /// - Returns: Array of suggested corrections
    func getSuggestions(for word: String) -> [String] {
        // First, check if we have a historical correction
        if let userCorrection = userCorrectionHistory[word] {
            return [userCorrection]
        }
        
        // Check spelling
        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelledRange = spellChecker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: "en")
        
        if misspelledRange.location != NSNotFound {
            let suggestions = spellChecker.guesses(
                forWordRange: misspelledRange,
                in: word,
                language: "en") ?? []
            
            return suggestions
        }
        
        return []
    }
    
    /// Learn from user correction to improve future suggestions
    /// - Parameters:
    ///   - originalWord: The incorrect word
    ///   - correctedWord: The user's correction
    func learnCorrection(originalWord: String, correctedWord: String) {
        userCorrectionHistory[originalWord] = correctedWord
    }
    
    // MARK: - Private Methods
    
    /// Check for spelling errors
    /// - Parameter word: The word to check
    /// - Returns: Probability of spelling error (0.0-1.0)
    private func checkSpellingError(_ word: String) -> Double {
        // Skip very short words or numbers
        if word.count <= 1 || word.allSatisfy({ $0.isNumber }) {
            return 0.0
        }
        
        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelledRange = spellChecker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: "en")
        
        if misspelledRange.location != NSNotFound {
            // Word is misspelled - calculate probability based on how many characters differ
            // from the closest suggestion
            if let suggestions = spellChecker.guesses(
                forWordRange: misspelledRange,
                in: word,
                language: "en"),
                !suggestions.isEmpty {
                
                let closestSuggestion = suggestions[0]
                let distance = calculateEditDistance(word, closestSuggestion)
                let normalizedDistance = Double(distance) / Double(max(word.count, closestSuggestion.count))
                
                // Map the distance to a probability (higher distance = higher probability of error)
                return min(normalizedDistance * 2.0, 1.0)
            }
            
            // No suggestions but still misspelled
            return 0.8
        }
        
        return 0.0
    }
    
    /// Calculate Levenshtein edit distance between two strings
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
