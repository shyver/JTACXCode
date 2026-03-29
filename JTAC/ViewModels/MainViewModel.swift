import SwiftUI
import Combine

class MainViewModel: ObservableObject {
    @Published var currentView: ViewType = .main
    @Published var isRecording = false
    @Published var liveTranscript = ""
    @Published var transcriptHistory: [TranscriptEntry] = []
    @Published var missionData: MissionData?

    // Tracks how many segments have been confirmed so we know what to reject
    @Published var lastConfirmedIndex: Int = 0

    // Shared state: selected NineLine tab id (used by both collapsed + expanded views).
    // Note: kept as a raw string so MainViewModel doesn't depend on NineLineTabs target membership.
    @Published var selectedNineLineCategory: String = "nineLineBrief"

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
    
    /// One-shot signal for returning to the main menu (Home).
    /// ContentView observes this and flips AppScreen to `.home`.
    @Published var shouldReturnToHome: Bool = false

    /// One-shot signal for returning to mission setup (New Mission).
    /// ContentView observes this and flips AppScreen to `.newMission`.
    @Published var shouldReturnToNewMission: Bool = false
    
    init() {
        print("[MainViewModel] init called")
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

        audioManager.onSegmentCompleted = { [weak self] segment, fullText in
            guard let self else { return }

            print("[MainViewModel] onSegmentCompleted received. segment: '\(segment)', fullText: '\(fullText)'")
            if !segment.isEmpty {
                let entry = TranscriptEntry(text: segment, timestamp: Date())
                self.transcriptHistory.append(entry)
                print("[MainViewModel] Appended to transcriptHistory. Count is now \(self.transcriptHistory.count)")
            }
            
            // WE NO LONGER AUTO-PARSE HERE. Parsing happens when user clicks Confirm.
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
        print("[MainViewModel] Starting recording via AudioManager")
        do {
            try audioManager.startRecording()
        } catch {
            print("[MainViewModel] Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    private func stopRecording() {
        print("[MainViewModel] Stopping recording via AudioManager")
        // AudioRecordingManager.stopRecording() flushes any partial segment
        // via onSegmentCompleted before tearing down, so no manual save needed here.
        audioManager.stopRecording()
    }
    
    // Method to clear current transcript and reset parsed data
    func clearLiveTranscript() {
        liveTranscript = ""
        transcriptHistory.removeAll()
        lastConfirmedIndex = 0
        lastReportedFullText = ""
        jtacViewModel.reset()
    }
    
    // MARK: - Manual Interpretation
    
    /// Confirms the current transcript history and sends all messages for interpretation.
    func confirmTranscript() {
        print("[MainViewModel] confirmTranscript pressed.")
        lastConfirmedIndex = transcriptHistory.count
        
        let fullTextToParse = transcriptHistory.map { $0.text }.joined(separator: " ")
        print("[MainViewModel] Passing text to jtacViewModel.reparse: '\(fullTextToParse)'")
        jtacViewModel.reparse(fullText: fullTextToParse)
    }
    
    /// Rejects the unconfirmed portion of the transcript.
    func rejectUnconfirmedTranscript() {
        print("[MainViewModel] rejectUnconfirmedTranscript pressed.")
        if transcriptHistory.count > lastConfirmedIndex {
            transcriptHistory.removeSubrange(lastConfirmedIndex...)
            print("[MainViewModel] Rejected segments back to index \(lastConfirmedIndex).")
        }
    }
    
    func requestReturnToHome() {
        shouldReturnToHome = true
    }

    func consumeReturnToHomeRequest() {
        shouldReturnToHome = false
    }

    func requestReturnToNewMission() {
        shouldReturnToNewMission = true
    }

    func consumeReturnToNewMissionRequest() {
        shouldReturnToNewMission = false
    }

    // MARK: - Mission updates
    /// Updates the mission's CAS check-in abort code (provided mid-air).
    func updateAbortCode(_ newValue: String) {
        guard var mission = missionData else { return }
        mission.casCheckin.abortCode = newValue
        missionData = mission
    }
}
