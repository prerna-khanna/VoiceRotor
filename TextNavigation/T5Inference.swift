//
//  T5Inference.swift
//  TextNavigation
//

import Foundation

class T5Inference {
    // Use the API endpoint pattern from the Medium article
    private let apiUrl = "https://api-inference.huggingface.co/models/t5-small"
    private let apiKey = "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"
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

    func loadModel(completion: @escaping (Bool) -> Void) {
        // Simple test request to check if model is loaded
        let testInput = "Hello, world!"
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
        // Use a grammar correction-specific prompt
        let prompt = "grammar: \(sentence)"
        
        inferenceRequest(with: prompt) { result in
            switch result {
            case .success(let output):
                DispatchQueue.main.async {
                    completion(output)
                }
            case .failure(let error):
                print("Grammar correction failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    // Following the approach from the Medium article
    private func inferenceRequest(with text: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: apiUrl) else {
            completion(.failure(NSError(domain: "T5Inference", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0
        
        // Set headers as in the article
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
            }
            
            // Parse the response
            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstResult = jsonResponse.first,
                   let generatedText = firstResult["translation_text"] as? String {  // Change "generated_text" to "translation_text"
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
}
