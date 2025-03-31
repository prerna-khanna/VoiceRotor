import Foundation

class GestureRecognition {
    private var gyroBuffer: [Double] = []
    private let bufferSize: Int
    private let gestureTemplates: [[Double]]  = [[
        0.0273662902857841, 0.0096136642698253, 0.0299626335350401, 0.0203267142120236, 0.0150850646285773,
        0.0175197216339734, 0.0282312321457451, 0.0131611542109491, 0.0224213975679534, 0.0758647581049567,
        0.1077884075769018, 0.2463211093302544, 0.3428345052769407, 0.5637560983900718, 0.7229892117916004,
        1.6120192504807198, 1.873698185598805, 1.1709383045454491, 1.0498644495893024, 0.8442711493089323,
        0.99258967588361, 1.4664725058756314, 1.9410793576322516, 2.0984505831089457, 2.0944370635977974,
        2.487497191150644, 2.8369528475606884, 3.4690139207780986, 2.055509448883311, 1.210345862068267,
        1.561783960541736, 1.8114679936859084, 1.4989656682232668, 1.4643025229798616, 0.9552191609985268,
        0.5371748724867738, 0.266639588805185, 0.1650568307665377, 0.0647875709235766, 0.0447365225884726,
        0.1052103098580713, 0.0193779350393047, 0.017722997111184, 0.0670756464035376, 0.0646950657198886
    ]]
    private let recognitionThreshold: Double = 10.0 // Adjusted threshold for tighter matching

    private var recordingTemplate: [Double] = []
    private var isRecording = false
    
    init(bufferSize: Int = 20) {
        self.bufferSize = bufferSize
    }
    
    // Start recording a gesture
    func startRecording() {
        isRecording = true
        recordingTemplate.removeAll()
        print("Started recording gesture.")
    }
    
    // Stop recording and return the recorded template
    func stopRecording() -> [Double] {
        isRecording = false
        print("Stopped recording gesture.")
        return recordingTemplate
    }
    
    // Add new gyro data
    func addGyroData(rotationRateX: Double, rotationRateY: Double, rotationRateZ: Double) -> Bool {
        let magnitude = sqrt(rotationRateX * rotationRateX + rotationRateY * rotationRateY + rotationRateZ * rotationRateZ)
        
        if isRecording {
            // Add data to the recording template
            recordingTemplate.append(magnitude)
            print("Recording data: \(magnitude)")
        } else {
            // Add data to the buffer for recognition
            gyroBuffer.append(magnitude)
            if gyroBuffer.count > bufferSize {
                gyroBuffer.removeFirst()
            }
            // Check for gesture recognition
            let recognized = checkForGesture()
            if recognized {
                print("Gesture recognized.")
            }
            return recognized
        }
        
        return false
    }
    
    // Check if the current buffer matches any gesture template using DTW
    private func checkForGesture() -> Bool {
        guard gyroBuffer.count == bufferSize else {
            return false
        }
        
        for template in gestureTemplates {
            if dtwDistance(buffer: gyroBuffer, template: template) < recognitionThreshold {
                return true
            }
        }
        
        return false
    }
    
    // Dynamic Time Warping (DTW) algorithm
    private func dtwDistance(buffer: [Double], template: [Double]) -> Double {
        let m = buffer.count
        let n = template.count
        var dtw = Array(repeating: Array(repeating: Double.infinity, count: n + 1), count: m + 1)
        
        dtw[0][0] = 0.0
        
        for i in 1...m {
            for j in 1...n {
                let cost = abs(buffer[i - 1] - template[j - 1])
                dtw[i][j] = cost + min(dtw[i - 1][j],        // Insertion
                                       dtw[i][j - 1],        // Deletion
                                       dtw[i - 1][j - 1])    // Match
            }
        }
        //print(dtw[m][n])
        
        return dtw[m][n]
    }
    
    // Optional: Apply a noise reduction filter to the gyro data
    private func applyNoiseReduction(to data: [Double]) -> [Double] {
        // Example: Simple moving average filter
        let windowSize = 3
        guard data.count >= windowSize else { return data }
        
        var smoothedData = [Double]()
        for i in 0..<(data.count - windowSize + 1) {
            let window = data[i..<(i + windowSize)]
            let average = window.reduce(0, +) / Double(windowSize)
            smoothedData.append(average)
        }
        
        return smoothedData
    }
}
