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

    /// Tracks the full text from the last onSegmentCompleted callback so we
    /// can compute the display delta for transcriptHistory entries.
    private var lastReportedFullText = ""
    
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

        // onSegmentCompleted now delivers the FULL accumulated text of the
        // current recording session on every silence commit.  We:
        //  1. Extract only the NEW tail for the transcript history display.
        //  2. Send the full text to JTACViewModel for a clean reset-and-reparse.
        audioManager.onSegmentCompleted = { [weak self] fullText in
            guard let self else { return }

            // Compute the new portion for display history.
            let displayDelta: String
            if fullText.hasPrefix(self.lastReportedFullText),
               !self.lastReportedFullText.isEmpty {
                displayDelta = String(fullText.dropFirst(self.lastReportedFullText.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                displayDelta = fullText
            }
            if !displayDelta.isEmpty {
                let entry = TranscriptEntry(text: displayDelta, timestamp: Date())
                self.transcriptHistory.append(entry)
            }
            self.lastReportedFullText = fullText

            // Full re-parse — parser resets and processes everything.
            self.jtacViewModel.reparse(fullText: fullText)
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
        lastReportedFullText = ""
        jtacViewModel.reset()
    }
}