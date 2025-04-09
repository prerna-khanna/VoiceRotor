import Foundation

class T5Inference {
    // Use the Grammarly coedit-large model
    private let apiUrl = "https://api-inference.huggingface.co/models/grammarly/coedit-large"
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
        let testInput = "i has some apples in the kitchen"
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
        
        // The Grammarly model doesn't need a specific prefix unlike the previous model
        let prompt = text
        
        inferenceRequest(with: prompt, retryCount: maxRetries) { result in
            switch result {
            case .success(let output):
                // Verify the response is valid and in English
                if self.isValidEnglishResponse(output, originalText: text) {
                    DispatchQueue.main.async {
                        // Clean up the response
                        let cleanedOutput = self.cleanResponse(output)
                        print("T5: Corrected text from '\(text)' to '\(cleanedOutput)'")
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
        correctText(text, completion: completion)
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
        
        // Prepare payload for the Grammarly model
        let payload: [String: Any] = ["inputs": text]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }
        
        print("T5: Sending request to Grammarly model with text: \"\(text)\"")
        
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
            
            // Debug: print raw response
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("T5: Raw API response: \(rawResponse)")
            }
            
            // Parse the response - Grammarly model may have different output format
            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstResult = jsonResponse.first,
                   let generatedText = firstResult["generated_text"] as? String {
                    print("T5: Successfully parsed response: \(generatedText)")
                    completion(.success(generatedText))
                } else {
                    // Try alternate parsing for different response formats
                    if let rawResponse = String(data: data, encoding: .utf8) {
                        // Check if it's a simple string response (some models return this)
                        if rawResponse.count > 0 && !rawResponse.contains("{") && !rawResponse.contains("[") {
                            print("T5: Using raw response as correction: \(rawResponse)")
                            completion(.success(rawResponse))
                            return
                        }
                    }
                    
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
        // Skip empty responses
        if response.isEmpty {
            return false
        }
        
        // If the response is exactly the same as the original, there were no errors to correct
        if response == originalText {
            return true
        }
        
        // The Grammarly model should always return English text
        // Let's do some basic checks
        
        // Check for non-Latin characters (which would suggest non-English)
        let nonLatinCharCount = response.unicodeScalars.filter { !CharacterSet.latinExtended.contains($0) }.count
        if nonLatinCharCount > 5 {
            return false
        }
        
        // Grammarly model should provide reasonable length responses
        if response.count < 2 || response.count > originalText.count * 2 {
            return false
        }
        
        // If we made it here, assume it's valid
        return true
    }
    
    // Helper method to clean up responses
    private func cleanResponse(_ response: String) -> String {
        // Just trim whitespace for the Grammarly model
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// Extension to help with character validation
extension CharacterSet {
    static let latinExtended = CharacterSet(charactersIn: UnicodeScalar(0x0000)!...UnicodeScalar(0x024F)!)
}
