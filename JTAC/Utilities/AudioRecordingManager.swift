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
        request.contextualStrings = AudioRecordingManager.jtacContextualStrings
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

    // MARK: - JTAC Contextual Vocabulary

    /// Biases the recognizer toward JTAC vocabulary at capture time.
    /// Also includes known mis-hearing variants so the normalizer can catch them.
    static let jtacContextualStrings: [String] = [

        // ----- Phonetic alphabet -----
        "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf",
        "hotel", "india", "juliet", "kilo", "lima", "mike", "november",
        "oscar", "papa", "quebec", "romeo", "sierra", "tango", "uniform",
        "victor", "whiskey", "x-ray", "yankee", "zulu",

        // ----- Military number pronunciation -----
        "niner", "fife", "tree", "zero", "wun",
        "one one", "one two", "two one", "two two", "three one",

        // ----- Radio procedure -----
        "break", "break break", "copy", "roger", "wilco", "standby", "stand by",
        "say again", "I say again", "over", "out", "radio check",
        "lima charlie", "weak but readable", "loud and clear",
        "how copy", "good copy", "negative", "affirm", "acknowledge",
        "go ahead", "send it", "all stations", "net call",

        // ----- CAS control types -----
        "type one", "type two", "type three",
        "type one control", "type two control", "type three control",
        "type 1 control", "type 2 control", "type 3 control",
        "emergency CAS", "immediate", "deliberate",
        "checking in", "check in",

        // ----- Situation update -----
        "situation update", "SITREP", "sit rep",

        // ----- 9-Line triggers -----
        "nine line", "9 line", "niner line", "nine liner",

        // ----- 9-Line fields -----
        "initial point", "IP",
        "line one", "line two", "line three", "line four", "line five",
        "line six", "line seven", "line eight", "line nine",
        "heading", "attack heading", "final attack heading",
        "ingress", "egress", "egress direction",
        "offset", "elevation", "target elevation",
        "mark", "mark type", "say when tally", "say when ready",
        "tally", "tally smoke", "tally target", "no joy",
        "friendlies", "friendly position", "troops in contact", "troops and contact",
        "danger close",
        "remarks", "restrictions",
        "battle damage assessment", "BDA",
        "laser code", "laser on", "sparkle",
        "MGRS", "grid", "ten digit", "eight digit", "six digit",

        // ----- Brevity codes -----
        "cleared hot", "not cleared hot", "clear hot",
        "in hot", "in dry", "off dry",
        "rifle", "guns", "pickle", "laser",
        "splash", "shack", "hit",
        "abort", "abort abort abort",
        "bingo", "joker", "Winchester",
        "playtime", "fuel state",
        "visual", "blind",
        "engaged", "supporting",
        "contact", "tally target",
        "pop smoke", "red smoke", "green smoke", "yellow smoke", "purple smoke",
        "mark on top", "mark by smoke", "mark by laser",

        // ----- Aircraft / platforms -----
        "A-10", "Warthog", "Hawg",
        "F-16", "Viper",
        "F-18", "F/A-18", "Hornet",
        "F-15E", "Strike Eagle",
        "B-52", "B-1", "AC-130", "Spooky", "Ghostrider",
        "AH-64", "Apache",
        "MQ-9", "Reaper",
        "rotary", "fixed wing", "fast mover",

        // ----- Weapons -----
        "GBU-12", "GBU-31", "GBU-32", "GBU-38", "GBU-54",
        "JDAM", "Paveway",
        "Hellfire", "Brimstone", "Maverick",
        "APKWS", "Hydra",
        "twenty mike mike", "thirty mike mike",
        "twenty millimeter", "thirty millimeter",
        "Mk-82", "Mk-83", "Mk-84",

        // ----- Callsign structure -----
        "Axeman", "Viper", "Reaper", "Widow", "Dagger",
        "Saber", "Falcon", "Eagle", "Cougar", "Hawg",
        "flight lead", "dash two", "dash three", "dash four",

        // ----- Navigation / geometry -----
        "north", "south", "east", "west",
        "northeast", "northwest", "southeast", "southwest",
        "meters", "kilometers", "feet", "miles", "nautical miles",
        "altitude MSL", "altitude AGL",
        "azimuth", "bearing",
        "offset left", "offset right",
        "pull off north", "pull off south",
        "two seven zero", "three six zero", "one eight zero", "zero nine zero",

        // ----- Time -----
        "Zulu", "time on target", "TOT", "playtime fifteen", "playtime thirty",
        "fuel state", "bingo fuel",

        // ----- JTAC roles -----
        "JTAC", "J TAC", "FAC", "TACP", "ROMAD",
        "terminal attack control", "terminal controller",
        "nine line brief", "nine-line brief",
        "game plan", "gameplan",
        "authenticate", "authentication",
        "talk on", "reference",

        // ----- Common trailing phrases -----
        "request immediate", "request deliberate",
        "say when ready", "ready for tasking",
        "standby for nine line", "standby for tasking",
        "over and out",
    ]

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
