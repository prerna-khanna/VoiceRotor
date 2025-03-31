//
//  T5Inference.swift
//  TextNavigation
//
//  Created by Prerna Khanna on 3/27/25.
//

import Foundation

class T5Inference {
    private let apiUrl = "https://api-inference.huggingface.co/models/vennify/t5-base-grammar-correction"
    private let apiKey = Config.huggingFaceAPIToken //Replace with your actual Hugging Face API token
    private let maxRetries = 5
    private let retryDelay: TimeInterval = 5.0 // Retry after 5 seconds
    private var isModelLoaded = false
    private let modelLoadingQueue = DispatchQueue(label: "modelLoadingQueue", attributes: .concurrent)

    func loadModel(completion: @escaping (Bool) -> Void) {
        print("Loading model...")
        sendWarmUpRequest(retriesRemaining: maxRetries) { [weak self] success in
            guard let self = self else { return }
            self.modelLoadingQueue.async(flags: .barrier) {
                self.isModelLoaded = success
                print("Model loaded: \(success)")
                completion(success)
            }
        }
    }

    private func sendWarmUpRequest(retriesRemaining: Int, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: apiUrl) else {
            print("Invalid API URL")
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "POST"
        
        let json: [String: Any] = ["inputs": "Warm-up request"]
        let jsonData = try! JSONSerialization.data(withJSONObject: json)
        
        request.httpBody = jsonData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                print("Failed to get data: \(error?.localizedDescription ?? "Unknown error")")
                completion(false)
                return
            }
            
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("Warm-up API response: \(rawResponse)")
                
                if rawResponse.contains("Model vennify/t5-base-grammar-correction is currently loading") && retriesRemaining > 0 {
                    print("Model is loading, retrying in \(self.retryDelay) seconds... (\(retriesRemaining) retries left)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + self.retryDelay) {
                        self.sendWarmUpRequest(retriesRemaining: retriesRemaining - 1, completion: completion)
                    }
                    return
                }
            }
            
            completion(true)
        }
        
        task.resume()
    }

    func correctSentence(_ sentence: String, completion: @escaping (String?) -> Void) {
        // Wait until the model is loaded
        modelLoadingQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.modelLoadingQueue.sync { // Ensure that any writes to isModelLoaded are completed
                if !self.isModelLoaded {
                    print("Model is not yet loaded. Cannot proceed with inference.")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
            }

            // Proceed with sentence correction after confirming the model is loaded
            self.sendRequest(sentence, retriesRemaining: self.maxRetries, completion: completion)
        }
    }

    private func sendRequest(_ sentence: String, retriesRemaining: Int, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: apiUrl) else {
            print("Invalid API URL")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "POST"
        
        // Add the "grammar: " prefix as required by the model
        let prefixedSentence = "grammar: \(sentence)"
        let json: [String: Any] = ["inputs": prefixedSentence]
        let jsonData = try! JSONSerialization.data(withJSONObject: json)
        
        request.httpBody = jsonData
        
        print("Sending request to API with input sentence: '\(prefixedSentence)'")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                print("Failed to get data: \(error?.localizedDescription ?? "Unknown error")")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("Raw API response: \(rawResponse)")
                
                if rawResponse.contains("Model vennify/t5-base-grammar-correction is currently loading") && retriesRemaining > 0 {
                    print("Model is still loading, retrying in \(self.retryDelay) seconds... (\(retriesRemaining) retries left)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + self.retryDelay) {
                        self.sendRequest(sentence, retriesRemaining: retriesRemaining - 1, completion: completion)
                    }
                    return
                }
            }
            
            if let output = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]],
               let correctedText = output.first?["generated_text"] as? String {
                print("Received corrected sentence: '\(correctedText)'")
                DispatchQueue.main.async {
                    completion(correctedText)
                }
            } else {
                print("Failed to parse the response or no correction made.")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
        
        task.resume()
    }
}
