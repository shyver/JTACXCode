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

    /// Fired on the main thread with fully corrected text when silence ends a transmission.
    var onSegmentCompleted: ((String) -> Void)?

    /// Fired whenever low-confidence flags are found in a result.
    var onLowConfidenceDetected: (([( word: String, correction: String?, confidence: Float)]) -> Void)?

    // MARK: - Private

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private let corrector = SpeechCorrectionEngine.shared

    /// Generation counter — prevents stale callbacks from cancelled tasks.
    private var taskGeneration = 0

    /// Silence debounce work item.
    private var silenceWorkItem: DispatchWorkItem?

    /// Text confirmed from previous task cycles in this transmission.
    /// Prepended to every new partial result so a forced task restart never
    /// erases words the user already spoke.
    private var committedText = ""

    /// Dynamic silence threshold — extends for long 9-line readouts.
    private var silenceThreshold: TimeInterval {
        let wordCount = transcribedText.split(separator: " ").count
        return wordCount > 15 ? 3.0 : 1.8
    }

    // MARK: - Initialisation

    override init() {
        super.init()
        checkSpeechPermission()
        buildAllModels()
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

    // MARK: - Language Model Preparation

    private func buildAllModels() {
        guard #available(iOS 17, *) else { return }
        Task {
            await CustomLanguageModelBuilder.shared.prepareAll()
            print("[SpeechManager] All phase models ready")
        }
    }

    // MARK: - Phase Switching

    private func phaseDidChange() {
        guard isRecording else { return }
        // Gracefully cycle the recognition task so it picks up the new model.
        // The audio engine keeps running — no gap in audio capture.
        print("[SpeechManager] Phase → \(currentPhase.rawValue), cycling task")
        cycleRecognitionTask()
    }

    /// Ends the current recognition task and starts a fresh one.
    /// Called from: silence cutoff (transcribedText already flushed),
    ///              phase change (save in-progress text as committed prefix).
    private func cycleRecognitionTask() {
        // On a phase change, transcribedText still holds the in-progress words.
        // Save them as the committed prefix so the new task doesn't lose them.
        // (Silence cutoff already cleared both before calling here.)
        let partial = transcribedText.trimmingCharacters(in: .whitespaces)
        if !partial.isEmpty && committedText.isEmpty {
            committedText = partial
        }

        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        recognitionTask = nil
        recognitionRequest = nil
        startNewRecognitionTask()
    }

    // MARK: - Recording

    func startRecording() throws {
        #if targetEnvironment(simulator)
        isRecording = true
        simulateSegments()
        return
        #endif

        recognitionTask?.cancel()
        recognitionTask = nil
        committedText = ""   // fresh transmission — discard any leftover

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

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        engine.prepare()
        try engine.start()

        isRecording = true
        startNewRecognitionTask()
    }

    func stopRecording() {
        #if targetEnvironment(simulator)
        isRecording = false
        return
        #endif

        isRecording = false
        silenceWorkItem?.cancel()
        silenceWorkItem = nil

        // Combine committed text from any mid-task resets with the current partial.
        let partial = [committedText, transcribedText]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        committedText = ""
        transcribedText = ""
        if !partial.isEmpty {
            onSegmentCompleted?(partial)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }

    // MARK: - Recognition Task

    private func startNewRecognitionTask() {
        guard isRecording else { return }

        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        taskGeneration += 1
        let myGen = taskGeneration

        // Build request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = SpeechManager.contextualStrings

        // Apply per-phase language model (iOS 17+)
        if #available(iOS 17, *) {
            let phase = currentPhase
            Task {
                let cfg = await CustomLanguageModelBuilder.shared.configuration(for: phase)
                await MainActor.run {
                    guard self.taskGeneration == myGen else { return }
                    if let cfg = cfg {
                        request.customizedLanguageModel = cfg
                    }
                }
            }
        }

        // Force on-device — app must function fully offline
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }

        recognitionRequest = request

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self, self.taskGeneration == myGen else { return }

            DispatchQueue.main.async {
                guard self.taskGeneration == myGen else { return }

                if let result {
                    // Full correction pipeline
                    let corrected = self.corrector.correct(result)

                    // Prepend any committed prefix from a prior task cycle.
                    // committedText is cleared once embedded here so it is
                    // never double-counted by the silence cutoff.
                    let combined = [self.committedText, corrected.text]
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")

                    // CRITICAL: never wipe what's already on screen.
                    // iOS may emit an empty or shorter intermediate result
                    // while it reconsiders — ignore those to prevent
                    // the "text disappeared" glitch.
                    if !combined.isEmpty {
                        self.transcribedText = combined
                        self.committedText = ""   // now embedded in transcribedText
                    }

                    // Surface confidence alerts
                    if !corrected.lowConfidenceFlags.isEmpty {
                        self.onLowConfidenceDetected?(corrected.lowConfidenceFlags)
                    }
                    if corrected.hasCriticalLowConfidence {
                        self.criticalConfidenceAlert = true
                    }

                    if result.isFinal {
                        // iOS finished this task (time limit, noise, or normal end).
                        // The user may still be speaking — cycle immediately so
                        // continued words are captured rather than lost.
                        // Save current display text as the committed prefix for
                        // the replacement task; the silence timer handles the
                        // actual segment cutoff as normal.
                        let snapshot = self.transcribedText
                        if !snapshot.isEmpty {
                            self.committedText = snapshot
                        }
                        self.startNewRecognitionTask()
                    } else {
                        self.rescheduleSilenceCutoff()
                    }

                } else if error != nil, self.isRecording {
                    // Task died with an error (audio interruption, session reset).
                    // transcribedText already contains committedText embedded,
                    // so save the whole display text as the new committed prefix.
                    let snapshot = self.transcribedText.trimmingCharacters(in: .whitespaces)
                    if !snapshot.isEmpty {
                        self.committedText = snapshot
                    }
                    self.startNewRecognitionTask()
                }
            }
        }
    }

    // MARK: - Silence Detection

    private func rescheduleSilenceCutoff() {
        guard isRecording else { return }
        silenceWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isRecording else { return }
            // committedText is embedded in transcribedText by the time silence
            // fires (it was cleared on each result update).  Use transcribedText
            // directly; drop any leftover committedText as a safety net.
            let text = self.transcribedText.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else {
                // Nothing to send — just ensure accumulators are clean.
                self.committedText = ""
                return
            }

            self.transcribedText = ""
            self.committedText = ""   // segment is done — reset accumulator
            self.criticalConfidenceAlert = false
            self.onSegmentCompleted?(text)
            self.cycleRecognitionTask()
        }

        silenceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + silenceThreshold, execute: item)
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
                    self.onSegmentCompleted?(line)
                    self.transcribedText = ""
                }
            }
        }
    }
    #endif
}
