import AVFoundation
import Speech

class AudioRecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?

    /// Called on the main thread each time a speech pause marks the end of a transmission.
    var onSegmentCompleted: ((String) -> Void)?

    // Permission status
    @Published var speechPermissionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    // Silence detection — debounce approach
    /// Seconds with no new speech recognition results before a segment is finalised.
    private let silenceThreshold: TimeInterval = 1.8
    /// Cancelled and rescheduled every time the recognizer produces new text.
    /// Fires only when recognition has been quiet for silenceThreshold seconds.
    private var silenceWorkItem: DispatchWorkItem?
    /// Incremented each time a new recognition task starts. Callbacks check they
    /// belong to the current generation before acting, so cancelled tasks can't
    /// trigger spurious restarts or overwrite state.
    private var taskGeneration = 0

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
        #if targetEnvironment(simulator)
        isRecording = true
        simulateSegments()
        return
        #endif

        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw RecordingError.audioEngineFailed
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            throw RecordingError.audioEngineFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        isRecording = true
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        startNewRecognitionTask()
    }

    /// Starts a fresh recognition request/task without touching the audio engine.
    /// Called once on session start and again automatically after every completed segment.
    private func startNewRecognitionTask() {
        guard isRecording else { return }

        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        taskGeneration += 1
        let myGeneration = taskGeneration

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            // Ignore callbacks from any task that has already been superseded
            guard self.taskGeneration == myGeneration else { return }

            DispatchQueue.main.async {
                guard self.taskGeneration == myGeneration else { return }

                if let result = result {
                    self.transcribedText = result.bestTranscription.formattedString
                    // Every new recognition result means speech is happening.
                    // Reschedule the silence cutoff from this moment.
                    self.rescheduleSilenceCutoff()
                } else if error != nil {
                    // Real unexpected failure — restart
                    if self.isRecording {
                        self.recognitionTask = nil
                        self.startNewRecognitionTask()
                    }
                }
            }
        }
    }

    // MARK: - Silence Detection (debounce)

    /// Called on the main thread every time the recognizer emits new text.
    /// Cancels any pending cutoff and schedules a fresh one silenceThreshold seconds out.
    /// If the recognizer goes quiet (no speech), the cutoff fires and ends the segment.
    private func rescheduleSilenceCutoff() {
        guard isRecording else { return }

        silenceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.isRecording else { return }
            let text = self.transcribedText.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return }

            // Don't wait for isFinal — take what we have, save it, and restart now.
            self.transcribedText = ""
            self.onSegmentCompleted?(text)

            self.recognitionTask?.cancel()
            self.recognitionRequest?.endAudio()
            self.recognitionTask = nil
            self.recognitionRequest = nil
            self.startNewRecognitionTask()
        }
        silenceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + silenceThreshold, execute: item)
    }

    func stopRecording() {
        #if targetEnvironment(simulator)
        isRecording = false
        return
        #endif

        isRecording = false
        silenceWorkItem?.cancel()
        silenceWorkItem = nil

        // Flush any partial text that hadn't reached isFinal yet.
        let partial = transcribedText.trimmingCharacters(in: .whitespaces)
        if !partial.isEmpty {
            onSegmentCompleted?(partial)
            transcribedText = ""
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }

    // MARK: - Simulator Helpers

    #if targetEnvironment(simulator)
    private func simulateSegments() {
        let lines = [
            "Axeman two-one, Hawg one-one checking in.",
            "Two by GBU-12, thirty mike-mike, playtime fifteen.",
            "Standby for tasking. Break.",
            "Type one control, troops in contact.",
        ]
        for (i, line) in lines.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i + 1) * 3.0) { [weak self] in
                guard let self = self, self.isRecording else { return }
                self.transcribedText = line
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    guard let self = self, self.isRecording else { return }
                    self.onSegmentCompleted?(line)
                    self.transcribedText = ""
                }
            }
        }
    }
    #endif

    // MARK: - Error Types

    enum RecordingError: Error {
        case recognitionRequestFailed
        case audioEngineFailed
        case permissionDenied

        var localizedDescription: String {
            switch self {
            case .recognitionRequestFailed: return "Unable to create recognition request"
            case .audioEngineFailed:        return "Unable to create audio engine"
            case .permissionDenied:         return "Microphone or speech recognition permission denied"
            }
        }
    }
}
