//
//  T5Inference.swift
//  TextNavigation
//

import Foundation

class T5Inference {
    // Use the grammar correction specific model
    private let apiUrl = "https://api-inference.huggingface.co/models/vennify/t5-base-grammar-correction"
    private let apiKey: String
    private var isModelLoaded = false
    private let modelLoadingQueue = DispatchQueue(label: "modelLoadingQueue", attributes: .concurrent)
    private let maxRetries = 2
    
    // Public property to check if model is loaded
    var modelIsLoaded: Bool {
        var result = false
        modelLoadingQueue.sync {
            result = isModelLoaded
        }
        return result
    }
    
    init() {
        // Get API key from Config
        self.apiKey = Config.huggingFaceAPIToken
    }

    func loadModel(completion: @escaping (Bool) -> Void) {
        // Simple test request to check if model is loaded
        let testInput = "grammar: i has appls in tha kitchen"
        inferenceRequest(with: testInput, retryCount: maxRetries) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(_):
                self.modelLoadingQueue.async(flags: .barrier) {
                    self.isModelLoaded = true
                    print("T5: Model loaded successfully")
                    completion(true)
                }
            case .failure(let error):
                self.modelLoadingQueue.async(flags: .barrier) {
                    self.isModelLoaded = false
                    print("T5: Model loading failed: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }

    // General correction method (handles both spelling and grammar)
    func correctText(_ text: String, completion: @escaping (String?) -> Void) {
        // Skip empty text
        guard !text.isEmpty else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        
        // Use the grammar prefix that the model expects
        let prompt = "grammar: \(text)"
        
        inferenceRequest(with: prompt, retryCount: maxRetries) { result in
            switch result {
            case .success(let output):
                // Verify the response is valid and in English
                if self.isValidEnglishResponse(output, originalText: text) {
                    DispatchQueue.main.async {
                        // Clean up the response
                        let cleanedOutput = self.cleanResponse(output)
                        completion(cleanedOutput)
                    }
                } else {
                    print("T5: Text correction failed: Response not in English or invalid")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            case .failure(let error):
                print("T5: Text correction failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    // Alias for backward compatibility
    func correctSentence(_ sentence: String, completion: @escaping (String?) -> Void) {
        correctText(sentence, completion: completion)
    }
    
    // Method specifically focused on spelling corrections
    func correctSpelling(_ text: String, completion: @escaping (String?) -> Void) {
        // Skip empty text
        guard !text.isEmpty else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        
        // Use a prompt that emphasizes spelling correction
        let prompt = "grammar: \(text)"  // Using grammar prompt works for spelling too
        
        inferenceRequest(with: prompt, retryCount: maxRetries) { result in
            switch result {
            case .success(let output):
                if self.isValidEnglishResponse(output, originalText: text) {
                    DispatchQueue.main.async {
                        let cleanedOutput = self.cleanResponse(output)
                        completion(cleanedOutput)
                    }
                } else {
                    print("T5: Spelling correction failed: Response not in English or invalid")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            case .failure(let error):
                print("T5: Spelling correction failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    // Enhanced request method with retry logic
    private func inferenceRequest(with text: String, retryCount: Int, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: apiUrl) else {
            completion(.failure(NSError(domain: "T5Inference", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0  // Reduced timeout for better user experience
        
        // Set headers
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
        
        // Create and start the task
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // Handle network error with retry
            if let error = error {
                print("T5: Network error: \(error.localizedDescription)")
                
                if retryCount > 0 {
                    print("T5: Retrying... (\(retryCount) attempts left)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        self.inferenceRequest(with: text, retryCount: retryCount - 1, completion: completion)
                    }
                    return
                }
                
                completion(.failure(error))
                return
            }
            
            // Check for model loading status (may need retry)
            if let data = data, let rawResponse = String(data: data, encoding: .utf8),
               rawResponse.contains("loading") || rawResponse.contains("still loading") {
                
                if retryCount > 0 {
                    print("T5: Model still loading, retrying in 1 second... (\(retryCount) attempts left)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        self.inferenceRequest(with: text, retryCount: retryCount - 1, completion: completion)
                    }
                    return
                }
            }
            
            // Check for HTTP error status codes
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                let errorMessage = "T5: HTTP error: \(httpResponse.statusCode)"
                print(errorMessage)
                
                // Retry for server errors (5xx) but not client errors (4xx)
                if httpResponse.statusCode >= 500 && retryCount > 0 {
                    print("T5: Server error, retrying... (\(retryCount) attempts left)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        self.inferenceRequest(with: text, retryCount: retryCount - 1, completion: completion)
                    }
                    return
                }
                
                completion(.failure(NSError(
                    domain: "T5Inference",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: errorMessage]
                )))
                return
            }
            
            // Ensure we have data
            guard let data = data else {
                print("T5: No data received")
                completion(.failure(NSError(domain: "T5Inference", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            // Parse the response
            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstResult = jsonResponse.first,
                   let generatedText = firstResult["generated_text"] as? String {
                    print("T5: Successfully parsed response: \(generatedText)")
                    completion(.success(generatedText))
                } else {
                    print("T5: Invalid response format")
                    
                    // Try again if we have retries left
                    if retryCount > 0 {
                        print("T5: Retrying with different format... (\(retryCount) attempts left)")
                        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                            self.inferenceRequest(with: text, retryCount: retryCount - 1, completion: completion)
                        }
                        return
                    }
                    
                    completion(.failure(NSError(domain: "T5Inference", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                }
            } catch {
                print("T5: JSON parsing error: \(error.localizedDescription)")
                
                // Try again for parsing errors
                if retryCount > 0 {
                    print("T5: Retrying after parsing error... (\(retryCount) attempts left)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        self.inferenceRequest(with: text, retryCount: retryCount - 1, completion: completion)
                    }
                    return
                }
                
                completion(.failure(error))
            }
        }.resume()
    }
    
    // Helper method to verify the response is valid English
    private func isValidEnglishResponse(_ response: String, originalText: String) -> Bool {
        // Check if response contains the original prompt
        if response.contains("grammar:") || response.contains("fix spelling:") {
            return false
        }
        
        // Check if response is in German or other non-English language
        let commonGermanWords = ["ich", "habe", "sind", "und", "der", "die", "das", "für", "mit", "Grammatik"]
        for word in commonGermanWords {
            if response.contains(word) {
                return false
            }
        }
        
        // Check for common English words
        let commonEnglishWords = ["I", "have", "the", "is", "are", "and", "to", "for", "with"]
        for word in commonEnglishWords {
            if response.contains(word) {
                return true
            }
        }
        
        // Fallback to checking if response is different from input but still similar
        if response != originalText && response.count > 2 {
            return true
        }
        
        return false
    }
    
    // Helper method to clean up responses
    private func cleanResponse(_ response: String) -> String {
        // Remove any prefixes that might be artifacts from the model
        var cleaned = response
            .replacingOccurrences(of: "grammar:", with: "")
            .replacingOccurrences(of: "Grammar:", with: "")
            .replacingOccurrences(of: "fix spelling:", with: "")
            .replacingOccurrences(of: "Fix spelling:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If the cleaned result is empty, return the original response
        if cleaned.isEmpty {
            return response
        }
        
        return cleaned
    }
}
