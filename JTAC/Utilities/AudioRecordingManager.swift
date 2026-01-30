import AVFoundation
import Speech

class AudioRecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?
    
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    // Permission status
    @Published var speechPermissionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        checkSpeechPermission()
    }
    
    // MARK: - Permission Handling
    
    func checkSpeechPermission() {
        speechPermissionStatus = SFSpeechRecognizer.authorizationStatus()
    }
    
    func requestSpeechPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                self.speechPermissionStatus = status
                completion(status == .authorized)
            }
        }
    }
    
    // MARK: - Recording & Transcription
    
    func startRecording() throws {
        // Check if running in simulator
        #if targetEnvironment(simulator)
        // For simulator, just simulate recording without actual audio
        isRecording = true
        // Simulate some transcription for testing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.transcribedText = "Simulated transcription in iOS Simulator..."
        }
        return
        #endif
        
        // Cancel any previous task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create and configure the speech recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            throw RecordingError.recognitionRequestFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Create audio engine and input node
        audioEngine = AVAudioEngine()
        
        guard let audioEngine = audioEngine else {
            throw RecordingError.audioEngineFailed
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Verify format is valid
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            throw RecordingError.audioEngineFailed
        }
        
        // Install tap on the audio engine
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        // Prepare and start the audio engine
        audioEngine.prepare()
        try audioEngine.start()
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                DispatchQueue.main.async {
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }
            
            if error != nil || result?.isFinal == true {
                audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }
        
        isRecording = true
    }
    
    func stopRecording() {
        #if targetEnvironment(simulator)
        isRecording = false
        return
        #endif
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        
        isRecording = false
    }
    
    // MARK: - Error Types
    
    enum RecordingError: Error {
        case recognitionRequestFailed
        case audioEngineFailed
        case permissionDenied
        
        var localizedDescription: String {
            switch self {
            case .recognitionRequestFailed:
                return "Unable to create recognition request"
            case .audioEngineFailed:
                return "Unable to create audio engine"
            case .permissionDenied:
                return "Microphone or speech recognition permission denied"
            }
        }
    }
}
