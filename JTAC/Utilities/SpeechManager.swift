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

    /// Fired on the main thread with the **full accumulated text** of the
    /// current recording session whenever a silence commit or stop occurs.
    /// Callers should treat each invocation as a complete snapshot — not
    /// an incremental segment.  The parser should reset-and-reparse.
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

    /// Text accumulated from previous task cycles within the current transmission.
    /// Always kept in sync with transcribedText so nothing is ever invisible.
    /// Only cleared by stopRecording — never by a task restart or silence commit.
    private var displayPrefix = ""

    /// Dynamic silence threshold — extends as the transmission grows longer.
    /// Uses the total accumulated text (displayPrefix + current partial) so that
    /// long 9-line briefs delivered across multiple task cycles are not cut off
    /// prematurely between lines.
    private var silenceThreshold: TimeInterval {
        let totalText = (displayPrefix + " " + transcribedText)
            .split(separator: " ")
            .filter { !$0.isEmpty }
        let wordCount = totalText.count
        switch wordCount {
        case 0..<8:  return 3.5   // short phrase — still absorbs a thinking pause
        case 8..<20: return 5.0   // mid-length / entering 9-line groups
        default:     return 6.0   // long 9-line / SITREP — don't cut between lines
        }
    }

    // MARK: - Initialisation

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
            silenceWorkItem?.cancel()
            silenceWorkItem = nil
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
            recognitionRequest = nil
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
                    // Reinstall the tap and restart the engine since it was stopped.
                    self.audioEngine?.inputNode.removeTap(onBus: 0)
                    let fmt = self.audioEngine?.inputNode.outputFormat(forBus: 0)
                    if let fmt, fmt.sampleRate > 0 {
                        self.audioEngine?.inputNode.installTap(
                            onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
                            self?.recognitionRequest?.append(buf)
                        }
                    }
                    try self.audioEngine?.start()
                    self.restartTaskInPlace()
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
        commitAndContinue()
    }

    /// Restarts the recognition task without ending the current transmission.
    /// displayPrefix absorbs whatever is on screen so it stays visible.
    /// The silence timer is the ONLY thing that ends a transmission.
    private func restartTaskInPlace() {
        // Snapshot current display text into the prefix so the operator
        // never sees anything disappear between task cycles.
        let current = transcribedText.trimmingCharacters(in: .whitespaces)
        print("[SpeechManager] restartTaskInPlace  transcribed=(\(current.prefix(60)))  prefix=(\(displayPrefix.prefix(40)))")
        if !current.isEmpty {
            displayPrefix = current
        }

        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        recognitionTask = nil
        recognitionRequest = nil
        startNewRecognitionTask()
    }

    /// Commits the **full accumulated text** to the parser and restarts the
    /// recognition task **without clearing the display**.  The operator always
    /// sees all text from this recording session.
    ///
    /// The callback receives the complete `transcribedText` snapshot each time.
    /// The receiving parser is expected to reset-and-reparse from scratch, which
    /// eliminates every possible incremental-dedup edge case.
    private func commitAndContinue() {
        silenceWorkItem?.cancel()
        silenceWorkItem = nil

        let fullText = transcribedText.trimmingCharacters(in: .whitespaces)
        print("[SpeechManager] commitAndContinue  fullText=(\(fullText.prefix(60)))  len=\(fullText.count)")
        guard !fullText.isEmpty else {
            restartTaskInPlace()
            return
        }

        // Always send the full accumulated text.
        onSegmentCompleted?(fullText)

        // Restart the recognition task but keep displayPrefix / transcribedText
        // intact so the operator never sees text disappear.
        restartTaskInPlace()
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
        displayPrefix = ""        // fresh recording session

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

        // Send the full accumulated text for a final re-parse, then tear down.
        let fullText = transcribedText.trimmingCharacters(in: .whitespaces)
        if !fullText.isEmpty {
            onSegmentCompleted?(fullText)
        }
        transcribedText = ""
        displayPrefix = ""

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
                    let corrected = self.corrector.correct(result)

                    if result.isFinal {
                        // ── Involuntary task end (iOS time/noise limit) ────────
                        // iOS fires isFinal on every natural pause, often within
                        // 1–2 seconds of silence.  This is the PRIMARY commit
                        // path — NOT the silence timer (which isFinal pre-empts
                        // by cancelling it via the task restart).
                        //
                        // Use whichever text is longer — iOS sometimes shortens
                        // on its final pass.
                        let best = corrected.text.count >= self.transcribedText.count
                            ? corrected.text : self.transcribedText
                        let trimmed = best.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            self.transcribedText = trimmed
                        }
                        print("[SpeechManager] isFinal → commitAndContinue  text=(\(self.transcribedText.prefix(80)))")

                        if !corrected.lowConfidenceFlags.isEmpty {
                            self.onLowConfidenceDetected?(corrected.lowConfidenceFlags)
                        }
                        if corrected.hasCriticalLowConfidence {
                            self.criticalConfidenceAlert = true
                        }

                        if self.isRecording {
                            // Commit text to parser AND restart task.
                            // commitAndContinue sends the full accumulated text
                            // then calls restartTaskInPlace (preserves display).
                            self.commitAndContinue()
                        }

                    } else {
                        // ── Normal partial result ──────────────────────────────
                        // Prepend the accumulated prefix from previous task cycles
                        // so the display always shows the full transmission so far.
                        let newText = corrected.text.trimmingCharacters(in: .whitespaces)
                        if newText.isEmpty {
                            // Empty partial — iOS is reconsidering. Keep showing
                            // whatever we have; do not blank the screen.
                        } else if self.displayPrefix.isEmpty {
                            self.transcribedText = newText
                        } else {
                            self.transcribedText = self.displayPrefix + " " + newText
                        }

                        if !corrected.lowConfidenceFlags.isEmpty {
                            self.onLowConfidenceDetected?(corrected.lowConfidenceFlags)
                        }
                        if corrected.hasCriticalLowConfidence {
                            self.criticalConfidenceAlert = true
                        }
                        self.rescheduleSilenceCutoff()
                    }

                } else if self.isRecording {
                    // ── Task died (error OR iOS nil/nil cancellation) ──────────
                    // Commit whatever we have so the parser stays current, then
                    // restart the task transparently.
                    print("[SpeechManager] task died → commitAndContinue  text=(\(self.transcribedText.prefix(60)))")
                    self.commitAndContinue()
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
            // Commit new text to the parser but keep the display intact.
            // The operator should never see text vanish mid-recording.
            self.commitAndContinue()
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
