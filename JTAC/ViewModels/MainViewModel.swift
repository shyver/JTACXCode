import SwiftUI
import Combine

class MainViewModel: ObservableObject {
    @Published var currentView: ViewType = .main
    @Published var isRecording = false
    @Published var liveTranscript = ""
    @Published var transcriptHistory: [TranscriptEntry] = []
    
    @Published var permissionManager = PermissionManager()
    let audioManager = AudioRecordingManager()
    
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
        // Subscribe to audio manager's transcribed text
        audioManager.$transcribedText
            .sink { [weak self] text in
                self?.liveTranscript = text
            }
            .store(in: &cancellables)
        
        // Subscribe to recording status
        audioManager.$isRecording
            .sink { [weak self] recording in
                self?.isRecording = recording
            }
            .store(in: &cancellables)
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
            print("Started recording and transcription...")
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    private func stopRecording() {
        audioManager.stopRecording()
        
        // Save the transcript to history
        if !liveTranscript.isEmpty {
            let entry = TranscriptEntry(text: liveTranscript, timestamp: Date())
            transcriptHistory.append(entry)
        }
        
        print("Stopped recording...")
    }
    
    // Method to clear current transcript
    func clearLiveTranscript() {
        liveTranscript = ""
    }
}