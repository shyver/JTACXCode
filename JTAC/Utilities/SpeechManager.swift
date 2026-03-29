import AVFoundation
import Speech
import Combine

// MARK: - SpeechManager
//
// Central coordinator for offline JTAC speech recognition.
//
// Responsibilities:
//   • Own the AVAudioEngine and SFSpeechRecognizer lifecycle
//   • Switch the active CustomLanguageModelBuilder phase model when JTACPhase changes
//   • Run every recognition result through SpeechCorrectionEngine
//   • Publish corrected live text and low-confidence alerts
//   • Fire onSegmentCompleted with fully corrected text for JTACParser
//
// Relationship to other types:
//   SpeechManager → CustomLanguageModelBuilder  (gets per-phase LM configs)
//   SpeechManager → SpeechCorrectionEngine      (corrects every result)
//   SpeechManager → JTACParser (via onSegmentCompleted callback)
//
// ── Offline guarantee ──────────────────────────────────────────────────────
// requiresOnDeviceRecognition = true is set on every request.
// CustomLanguageModelBuilder never touches the network.
// No URLSession or network calls anywhere in this file.

final class SpeechManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isRecording = false
    @Published var transcribedText = ""          // live corrected display text
    @Published var errorMessage: String?
    @Published var speechPermissionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    /// Set when a low-confidence segment contains a safety-critical phrase.
    /// UI should surface this prominently so the operator can verify.
    @Published var criticalConfidenceAlert = false

    /// Current JTAC phase — changing this switches the active language model
    /// on the next recognition task cycle.
    @Published var currentPhase: JTACPhase = .general {
        didSet { if oldValue != currentPhase { phaseDidChange() } }
    }

    // MARK: - Callbacks

    /// Fired on the main thread when a natural speech pause occurs.
    /// Passes the newly completed segment for chat bubbles, and the full transcript for the parser.
    var onSegmentCompleted: ((_ newSegment: String, _ fullText: String) -> Void)?

    /// Fired whenever low-confidence flags are found in a result.
    var onLowConfidenceDetected: (([( word: String, correction: String?, confidence: Float)]) -> Void)?

    // MARK: - Private

    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private var committedSegments: [String] = []
    
    // Generation counter to prevent old canceled tasks from triggering a restart loop.
    private var taskGeneration = 0
    private var silenceTimer: Timer?
    
    // Audio buffering layer to guarantee zero audio dropped when transitioning speech tasks
    private let audioQueue = DispatchQueue(label: "com.jtac.audioQueue")
    private var activeRequest: SFSpeechAudioBufferRecognitionRequest?
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    
    // Safety lock
    private var isTeardownInProgress = false

    override init() {
        super.init()
        checkSpeechPermission()
        buildAllModels()
        observeAudioSessionInterruptions()
    }

    // MARK: - Permissions

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

    // MARK: - Audio Session Interruption Handling

    private func observeAudioSessionInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    /// Called when a phone call, alarm, Siri, or other app interrupts the session.
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // Interruption started — tear down cleanly without firing onSegmentCompleted
            // (the operator is no longer transmitting).  Stay in "recording" intent
            // state so we can resume automatically.
            print("[SpeechManager] Audio interruption began")
            audioQueue.async {
                self.activeRequest?.endAudio()
                self.activeRequest = nil
                self.pendingBuffers.removeAll()
            }
            recognitionTask?.cancel()
            recognitionTask = nil
            audioEngine?.stop()
            // Do NOT removeTap — we will reuse the engine on resume.

        case .ended:
            print("[SpeechManager] Audio interruption ended")
            guard isRecording else { return }
            // Wait one beat for the session to fully recover, then restart.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.isRecording else { return }
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    try self.audioEngine?.start()
                    self.startNewRecognitionTask()
                } catch {
                    self.errorMessage = "Could not resume after interruption: \(error.localizedDescription)"
                }
            }

        @unknown default:
            break
        }
    }

    /// Called when iOS resets media services (rare but catastrophic without handling).
    @objc private func handleMediaServicesReset() {
        print("[SpeechManager] Media services reset")
        guard isRecording else { return }
        // Full teardown and restart.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.stopRecording()
            self?.errorMessage = "Audio system was reset. Please tap record to resume."
        }
    }

    // MARK: - Language Model Preparation

    private func buildAllModels() {
        // Obsolete custom language model builder removed. Natively handles speech.
    }

    // MARK: - Phase Switching

    private func phaseDidChange() {
        guard isRecording else { return }
        print("[SpeechManager] Phase → \(currentPhase.rawValue), cleanly cycle task")
        audioQueue.async {
            print("[SpeechManager][audioQueue] Calling endAudio() for phase change")
            self.activeRequest?.endAudio()
            self.activeRequest = nil
        }
    }

    /// Helper to get the total text
    private func getFullText() -> String {
        return (committedSegments + [transcribedText])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Recording

    func startRecording() throws {
        print("[SpeechManager] startRecording called")
        #if targetEnvironment(simulator)
        isRecording = true
        isTeardownInProgress = false
        simulateSegments()
        return
        #endif

        isTeardownInProgress = false

        audioQueue.sync {
            activeRequest = nil
            pendingBuffers.removeAll()
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        transcribedText = ""
        committedSegments = []
        
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        // Advisory 16 kHz mono request — matches Speech framework's internal format.
        try? session.setPreferredSampleRate(16000)
        try? session.setPreferredInputNumberOfChannels(1)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { throw SpeechError.audioEngineFailed }

        let inputNode = engine.inputNode
        let fmt = inputNode.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            throw SpeechError.audioEngineFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, time in
            guard let self = self else { return }
            self.audioQueue.async {
                if let req = self.activeRequest {
                    // print("[SpeechManager] Audio tape tick -> appending to ACTIVE req")
                    req.append(buffer)
                } else {
                    // print("[SpeechManager] Audio tape tick -> appending to PENDING buffers")
                    self.pendingBuffers.append(buffer)
                }
            }
        }

        engine.prepare()
        try engine.start()

        isRecording = true
        print("[SpeechManager] Audio engine started, calling startNewRecognitionTask")
        startNewRecognitionTask()
    }

    func stopRecording() {
        print("[SpeechManager] stopRecording called")
        #if targetEnvironment(simulator)
        isRecording = false
        return
        #endif

        isRecording = false
        isTeardownInProgress = true
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioQueue.sync {
            print("[SpeechManager][audioQueue] stopRecording sync block - ending audio and clearing pendings")
            activeRequest?.endAudio()
            activeRequest = nil
            pendingBuffers.removeAll()
        }

        // Send the final segment right away on manual stop
        let segment = transcribedText.trimmingCharacters(in: .whitespaces)
        print("[SpeechManager] stopRecording trimming final segment: '\(segment)'")
        if !segment.isEmpty {
            committedSegments.append(segment)
            onSegmentCompleted?(segment, getFullText())
        }
        transcribedText = ""

        recognitionTask?.cancel()
        recognitionTask = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }

    // MARK: - Recognition Task

    private func startNewRecognitionTask() {
        guard isRecording, !isTeardownInProgress else {
            print("[SpeechManager] startNewRecognitionTask aborted. isRecording: \(isRecording), isTeardownInProgress: \(isTeardownInProgress)")
            return
        }
        
        print("[SpeechManager] Creating SFSpeechRecognitionTask for generation \(taskGeneration + 1)")
        
        taskGeneration += 1
        let currentGeneration = taskGeneration

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = SpeechManager.contextualStrings

        // Force on-device — app must function fully offline
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            // Ignore results from old tasks
            guard self.taskGeneration == currentGeneration else {
                print("[SpeechManager] Warning: Ignoring result for old generation \(currentGeneration). Current is \(self.taskGeneration)")
                return
            }

            DispatchQueue.main.async {
                guard self.taskGeneration == currentGeneration else { return }
                
                if let result = result {
                    let rawText = result.bestTranscription.formattedString
                    let textLength = rawText.count
                    print("[SpeechManager] Gen \(currentGeneration) partial result. length=\(textLength), isFinal=\(result.isFinal), text: '\(rawText)'")
                    
                    let newText = rawText.trimmingCharacters(in: .whitespaces)

                    // APPLE BUG WORKAROUND 1:
                    // SFSpeechRecognizer sometimes yields a completely empty string uniquely on the
                    // very final `isFinal=true` tick after `endAudio()` is called on-device.
                    // We must not let it overwrite the text we just spent the last 10 seconds building!
                    if newText.isEmpty && !self.transcribedText.isEmpty {
                        print("[SpeechManager] ⚠️ Apple returned empty text! Preserving previously built text: '\(self.transcribedText)'")
                    } else {
                        // APPLE BUG WORKAROUND 2:
                        // SFSpeechRecognizer has a rolling buffer limit and will silently delete the front half
                        // of your sentence if you speak continuously.
                        // If the incoming text length violently shrinks by more than 50% on a long string,
                        // we MUST salvage what we had by instantly committing it to chat history
                        // before accepting the new short text.
                        let oldLength = self.transcribedText.count
                        let newLength = newText.count
                        if oldLength > 20 && newLength < (oldLength / 2) {
                            print("[SpeechManager] ⚠️ Apple buffer rolling detected! String cut from \(oldLength) to \(newLength). Pre-committing salvage: '\(self.transcribedText)'")
                            self.committedSegments.append(self.transcribedText)
                            self.onSegmentCompleted?(self.transcribedText, self.getFullText())
                        }
                        
                        self.transcribedText = newText
                    }

                    // 1.2-second silence cleanly cuts the request to force a final commit natively
                    // (Reduced from 2.0s to avoid aggressive buffer buildups)
                    if !self.transcribedText.isEmpty && !result.isFinal {
                        self.silenceTimer?.invalidate()
                        self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                            guard let self = self, self.isRecording, !self.isTeardownInProgress else { return }
                            print("[SpeechManager] 1.2-sec silence hit for Gen \(currentGeneration)! Signaling endAudio() to trigger commit gracefully.")
                            self.audioQueue.async {
                                print("[SpeechManager][audioQueue] Executing endAudio() from silence timer")
                                self.activeRequest?.endAudio()
                                self.activeRequest = nil
                            }
                        }
                    }

                    if result.isFinal {
                        print("[SpeechManager] isFinal == true natively for Gen \(currentGeneration). Saving segment -> '\(self.transcribedText)'")
                        let segment = self.transcribedText.trimmingCharacters(in: .whitespaces)
                        if !segment.isEmpty {
                            self.committedSegments.append(segment)
                            let fullText = self.getFullText()
                            print("[SpeechManager] Firing onSegmentCompleted. New Segment: '\(segment)', Full History: '\(fullText)'")
                            self.onSegmentCompleted?(segment, fullText)
                        } else {
                            print("[SpeechManager] isFinal was true but segment was empty.")
                        }
                        self.transcribedText = ""
                        self.silenceTimer?.invalidate()
                        
                        if self.isRecording && !self.isTeardownInProgress {
                            print("[SpeechManager] isRecording still true, launching new task")
                            self.startNewRecognitionTask()
                        }
                    }
                } else if let error = error {
                    // Code 216 means "No speech detected" (often triggers on endAudio with empty buffer)
                    let nsError = error as NSError
                    print("[SpeechManager] Task error on gen \(currentGeneration). Code: \(nsError.code), Desc: \(error.localizedDescription)")
                    
                    let curText = self.transcribedText.trimmingCharacters(in: .whitespaces)
                    if !curText.isEmpty {
                        print("[SpeechManager] Salvaging text on error: '\(curText)'")
                        self.committedSegments.append(curText)
                        self.onSegmentCompleted?(curText, self.getFullText())
                    }
                    self.transcribedText = ""
                    self.silenceTimer?.invalidate()

                    if self.isRecording && !self.isTeardownInProgress {
                        print("[SpeechManager] Relaunching task after error")
                        self.startNewRecognitionTask()
                    }
                }
            }
        }
        
        // Let the background audio queue take ownership of the request and flush anything generated during startup
        audioQueue.async {
            print("[SpeechManager][audioQueue] Attaching active request to Gen \(currentGeneration)")
            self.activeRequest = request
            let pendingCount = self.pendingBuffers.count
            for buf in self.pendingBuffers {
                request.append(buf)
            }
            self.pendingBuffers.removeAll()
            print("[SpeechManager][audioQueue] Flushed \(pendingCount) pending buffers into request.")
        }
    }

    // MARK: - Contextual Strings (base list, supplements the LM)

    static let contextualStrings: [String] = [
        // NATO phonetic
        "alpha","bravo","charlie","delta","echo","foxtrot","golf",
        "hotel","india","juliet","kilo","lima","mike","november",
        "oscar","papa","quebec","romeo","sierra","tango","uniform",
        "victor","whiskey","x-ray","yankee","zulu",
        // Military numbers
        "niner","fife","tree","wun",
        "one one","one two","two one","two two","three one",
        // Radio procedure
        "break break","copy","roger","wilco","standby","stand by",
        "say again","I say again","over","out",
        "lima charlie","loud and clear","how copy","good copy",
        "negative","affirm","authenticate",
        // CAS
        "type one control","type two control","type three control",
        "type 1 control","type 2 control","type 3 control",
        "emergency CAS","immediate","deliberate",
        "checking in","check in",
        "SITREP","sit rep",
        // 9-line
        "nine line","9 line","niner line","nine liner",
        "initial point","IP",
        "line one","line two","line three","line four","line five",
        "line six","line seven","line eight","line nine",
        "attack heading","final attack heading",
        "ingress","egress","egress direction",
        "offset","elevation","target elevation",
        "tally","tally smoke","tally target","no joy",
        "friendlies","friendly position","troops in contact",
        "danger close","remarks","restrictions",
        "battle damage assessment","BDA",
        "laser code","laser on","sparkle",
        "MGRS","grid",
        // SITREP / Situation Update
        "situation update","SITREP",
        "threats","MANPADS","small arms","small arms fire",
        "machine gun","mortar fire","RPG","IED","VBIED","AAA","SAM",
        "BMP","BTR","technical","dismounts",
        "platoon","section","company","battalion",
        "clearance authority","arty cold","arty hot","COLD","HOT",
        // Brevity
        "cleared hot","not cleared hot","clear hot",
        "in hot","in dry","off dry",
        "rifle","guns","pickle",
        "splash","shack","abort abort abort",
        "bingo","joker",
        "pop smoke","red smoke","green smoke","yellow smoke","purple smoke",
        // Platforms
        "A-10","Warthog","Hawg",
        "F-16","Viper","F/A-18","Hornet","F-15E",
        "B-52","B-1","AC-130","Spooky","Ghostrider",
        "AH-64","Apache","MQ-9","Reaper",
        // Weapons
        "GBU-12","GBU-31","GBU-32","GBU-38","GBU-54",
        "JDAM","Paveway","Hellfire","Brimstone","Maverick","APKWS","Hydra",
        "thirty mike-mike","twenty mike-mike","Mk-82","Mk-83","Mk-84",
        // Callsigns
        "Axeman","Hawg","Viper","Reaper","Widow","Dagger",
        "Saber","Falcon","Eagle","Cougar","Panther","Warlord",
        "Ares","Bone","Slayer","Striker",
        "flight lead","dash two","dash three","dash four",
        // Quantities
        "two by","four by","one by","three by","six by",
        "2x","4x","1x","3x",
        // Navigation
        "north","south","east","west",
        "northeast","northwest","southeast","southwest",
        "altitude MSL","altitude AGL",
        "two seven zero","three six zero","one eight zero","zero nine zero",
        // JTAC roles
        "JTAC","TACP","ROMAD","FAC",
        "terminal attack control",
        "game plan","authenticate","talk on",
        "standby for nine line","standby for tasking",
        "say when ready","ready for tasking",
    ]

    // MARK: - Error Types

    enum SpeechError: Error {
        case audioEngineFailed
        case permissionDenied

        var localizedDescription: String {
            switch self {
            case .audioEngineFailed:  return "Unable to start audio engine"
            case .permissionDenied:   return "Microphone or speech recognition permission denied"
            }
        }
    }

    // MARK: - Simulator Helpers

    #if targetEnvironment(simulator)
    private func simulateSegments() {
        let lines = [
            "Axeman two-one, Hawg one-one checking in.",
            "Two by GBU-12, thirty mike-mike, playtime fifteen.",
            "Standby for tasking. Break.",
            "Type one control, troops in contact.",
            "nine line, line one, two seven zero.",
            "Cleared hot. Rifle. Splash.",
            "BDA: shack, direct hit, end of mission.",
        ]
        for (i, line) in lines.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i + 1) * 3.0) { [weak self] in
                guard let self, self.isRecording else { return }
                self.transcribedText = line
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    guard let self, self.isRecording else { return }
                    self.committedSegments.append(line)
                    self.onSegmentCompleted?(line, self.getFullText())
                    self.transcribedText = ""
                }
            }
        }
    }
    #endif
}
