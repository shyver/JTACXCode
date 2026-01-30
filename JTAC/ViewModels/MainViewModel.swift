import SwiftUI
import Combine

class MainViewModel: ObservableObject {
    @Published var currentView: ViewType = .main
    @Published var isRecording = false
    
    let microphoneManager = MicrophonePermissionManager()
    
    enum ViewType {
        case main
        case liveTranscript
        case nineLine
        case map
    }
    
    func navigateTo(_ view: ViewType) {
        currentView = view
    }
    
    func toggleRecording() {
        if isRecording {
            // Stop recording
            stopRecording()
        } else {
            // Check permission before starting recording
            startRecordingWithPermission()
        }
    }
    
    private func startRecordingWithPermission() {
        switch microphoneManager.permissionStatus {
        case .granted:
            startRecording()
        case .denied:
            microphoneManager.showPermissionDeniedAlert = true
        case .undetermined:
            microphoneManager.requestPermission { [weak self] granted in
                if granted {
                    self?.startRecording()
                }
            }
        @unknown default:
            break
        }
    }
    
    private func startRecording() {
        isRecording = true
        // Add your recording logic here
        print("Started recording...")
    }
    
    private func stopRecording() {
        isRecording = false
        // Add your stop recording logic here
        print("Stopped recording...")
    }
}