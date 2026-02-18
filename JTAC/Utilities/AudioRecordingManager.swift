import AVFoundation
import Speech

// MARK: - AudioRecordingManager
//
// Compatibility shim — forwards every property and method to SpeechManager.
// Existing callers (MainViewModel, Views) require zero changes.
// New code should reference SpeechManager directly.

final class AudioRecordingManager: NSObject, ObservableObject {

    // Forwarded published state
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?
    @Published var speechPermissionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    /// Fired on the main thread with fully corrected text when a segment ends.
    var onSegmentCompleted: ((String) -> Void)? {
        get { _manager.onSegmentCompleted }
        set { _manager.onSegmentCompleted = newValue }
    }

    let _manager = SpeechManager()
    private var _obs: [Any] = []

    override init() {
        super.init()
        _obs.append(_manager.$isRecording.assign(to: \.isRecording, on: self))
        _obs.append(_manager.$transcribedText.assign(to: \.transcribedText, on: self))
        _obs.append(_manager.$errorMessage.assign(to: \.errorMessage, on: self))
        _obs.append(_manager.$speechPermissionStatus.assign(to: \.speechPermissionStatus, on: self))
    }

    func checkSpeechPermission()  { _manager.checkSpeechPermission() }

    func requestSpeechPermission(completion: @escaping (Bool) -> Void) {
        _manager.requestSpeechPermission(completion: completion)
    }

    func startRecording() throws  { try _manager.startRecording() }
    func stopRecording()          { _manager.stopRecording() }

    var currentPhase: JTACPhase {
        get { _manager.currentPhase }
        set { _manager.currentPhase = newValue }
    }

    static func quickNormalize(_ input: String) -> String {
        SpeechCorrectionEngine.shared.quickCorrect(input)
    }

    typealias RecordingError = SpeechManager.SpeechError
}
