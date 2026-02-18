import SwiftUI
import Combine

class MainViewModel: ObservableObject {
    @Published var currentView: ViewType = .main
    @Published var isRecording = false
    @Published var liveTranscript = ""
    @Published var transcriptHistory: [TranscriptEntry] = []
    
    @Published var permissionManager = PermissionManager()
    let audioManager = AudioRecordingManager()
    let jtacViewModel = JTACViewModel()
    
    private var cancellables = Set<AnyCancellable>()
    
    enum ViewType {
        case main
        case liveTranscript
        case nineLine
        case map
    }
    
    struct TranscriptEntry: Identifiable {
        let id = UUID()
        let text: String
        let timestamp: Date
    }
    
    init() {
        // Mirror live partial text into the view
        audioManager.$transcribedText
            .sink { [weak self] text in
                self?.liveTranscript = text
            }
            .store(in: &cancellables)

        // Mirror recording state
        audioManager.$isRecording
            .sink { [weak self] recording in
                self?.isRecording = recording
            }
            .store(in: &cancellables)

        // Each pause-terminated segment arrives here, becomes a history entry,
        // and is forwarded to JTACViewModel for structured parsing.
        audioManager.onSegmentCompleted = { [weak self] text in
            guard let self else { return }
            let entry = TranscriptEntry(text: text, timestamp: Date())
            self.transcriptHistory.append(entry)
            self.jtacViewModel.process(segment: text)
        }
    }
    
    func navigateTo(_ view: ViewType) {
        currentView = view
    }
    
    func returnToMain() {
        currentView = .main
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecordingWithPermission()
        }
    }
    
    private func startRecordingWithPermission() {
        // Check if we have all permissions
        if permissionManager.hasAllPermissions() {
            startRecording()
        } else {
            // Request permissions
            permissionManager.requestAllPermissions { [weak self] granted in
                if granted {
                    self?.startRecording()
                }
            }
        }
    }
    
    private func startRecording() {
        do {
            try audioManager.startRecording()
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    private func stopRecording() {
        // AudioRecordingManager.stopRecording() flushes any partial segment
        // via onSegmentCompleted before tearing down, so no manual save needed here.
        audioManager.stopRecording()
    }
    
    // Method to clear current transcript and reset parsed data
    func clearLiveTranscript() {
        liveTranscript = ""
        transcriptHistory.removeAll()
        jtacViewModel.reset()
    }
}