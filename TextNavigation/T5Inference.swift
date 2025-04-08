//
//  T5Inference.swift
//  TextNavigation
//

import Foundation

class T5Inference {
    // Use the API endpoint pattern from the Medium article
    private let apiUrl = "https://api-inference.huggingface.co/models/t5-small"
    private let apiKey: String
    private var isModelLoaded = false
    private let modelLoadingQueue = DispatchQueue(label: "modelLoadingQueue", attributes: .concurrent)
    
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
        let testInput = "Correct this sentence in English: Hello, world!"
        inferenceRequest(with: testInput) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(_):
                self.modelLoadingQueue.async(flags: .barrier) {
                    self.isModelLoaded = true
                    print("Model loaded successfully")
                    completion(true)
                }
            case .failure(let error):
                self.modelLoadingQueue.async(flags: .barrier) {
                    self.isModelLoaded = false
                    print("Model loading failed: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }

    func correctSentence(_ sentence: String, completion: @escaping (String?) -> Void) {
        // Use an English-specific grammar correction prompt
        let prompt = "Correct English grammar: \(sentence)"
        
        inferenceRequest(with: prompt) { result in
            switch result {
            case .success(let output):
                // Verify the response is valid and in English
                if self.isValidEnglishResponse(output, originalText: sentence) {
                    DispatchQueue.main.async {
                        // Clean up the response
                        let cleanedOutput = self.cleanResponse(output)
                        completion(cleanedOutput)
                    }
                } else {
                    print("Grammar correction failed: Response not in English or invalid")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            case .failure(let error):
                print("Grammar correction failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    // Following the approach from the Medium article without language parameter
    private func inferenceRequest(with text: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: apiUrl) else {
            completion(.failure(NSError(domain: "T5Inference", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0
        
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
        
        // Print debug info
        print("Sending request to: \(url.absoluteString)")
        print("With payload: \(text)")
        
        // Create and start the task
        URLSession.shared.dataTask(with: request) { data, response, error in
            // Handle network error
            if let error = error {
                print("Network error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            // Log HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status: \(httpResponse.statusCode)")
                
                // Check for error status codes
                if httpResponse.statusCode >= 400 {
                    let errorMessage = "HTTP error: \(httpResponse.statusCode)"
                    print(errorMessage)
                    completion(.failure(NSError(
                        domain: "T5Inference",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: errorMessage]
                    )))
                    return
                }
            }
            
            // Ensure we have data
            guard let data = data else {
                print("No data received")
                completion(.failure(NSError(domain: "T5Inference", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            // Debug: print raw response
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("Raw API response: \(rawResponse)")
                
                // Check for error in JSON
                if rawResponse.contains("error") {
                    print("API returned error: \(rawResponse)")
                    completion(.failure(NSError(
                        domain: "T5Inference",
                        code: -6,
                        userInfo: [NSLocalizedDescriptionKey: "API error: \(rawResponse)"]
                    )))
                    return
                }
                
                // Check if we got HTML
                if rawResponse.contains("<!DOCTYPE html>") || rawResponse.contains("<html") {
                    print("Received HTML instead of JSON")
                    completion(.failure(NSError(
                        domain: "T5Inference",
                        code: -5,
                        userInfo: [NSLocalizedDescriptionKey: "Received HTML instead of JSON"]
                    )))
                    return
                }
            }
            
            // Parse the response
            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstResult = jsonResponse.first,
                   let generatedText = firstResult["generated_text"] as? String {  // Changed from translation_text to generated_text
                    print("Successfully parsed response: \(generatedText)")
                    completion(.success(generatedText))
                } else {
                    print("Invalid response format")
                    completion(.failure(NSError(domain: "T5Inference", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                }
            } catch {
                print("JSON parsing error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }.resume()
    }
    
    // Helper method to verify the response is valid English
    private func isValidEnglishResponse(_ response: String, originalText: String) -> Bool {
        // Check if response contains the original prompt
        if response.contains("Correct English grammar:") || response.contains("grammar:") {
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
            .replacingOccurrences(of: "Correct English grammar:", with: "")
            .replacingOccurrences(of: "Grammar:", with: "")
            .replacingOccurrences(of: "Grammatik:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If the cleaned result is empty, return the original response
        if cleaned.isEmpty {
            return response
        }
        
        return cleaned
    }
}
