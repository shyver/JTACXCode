import AVFoundation
import Speech
import SwiftUI

class PermissionManager: ObservableObject {
    enum MicrophoneStatus {
        case undetermined
        case granted
        case denied
    }
    
    @Published var microphoneStatus: MicrophoneStatus = .undetermined
    @Published var speechStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var showPermissionAlert = false
    @Published var permissionAlertMessage = ""
    
    init() {
        checkPermissions()
    }
    
    func checkPermissions() {
        // Check microphone permission
        let micPermission = AVAudioApplication.shared.recordPermission
        switch micPermission {
        case .undetermined:
            microphoneStatus = .undetermined
        case .granted:
            microphoneStatus = .granted
        case .denied:
            microphoneStatus = .denied
        @unknown default:
            microphoneStatus = .undetermined
        }
        
        // Check speech recognition permission
        speechStatus = SFSpeechRecognizer.authorizationStatus()
    }
    
    func requestAllPermissions(completion: @escaping (Bool) -> Void) {
        requestMicrophonePermission { [weak self] micGranted in
            guard let self = self, micGranted else {
                completion(false)
                return
            }
            
            self.requestSpeechPermission { speechGranted in
                completion(speechGranted)
            }
        }
    }
    
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.microphoneStatus = granted ? .granted : .denied
                if !granted {
                    self.permissionAlertMessage = "Microphone access is required to record audio."
                    self.showPermissionAlert = true
                }
                completion(granted)
            }
        }
    }
    
    private func requestSpeechPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                self.speechStatus = status
                if status != .authorized {
                    self.permissionAlertMessage = "Speech recognition access is required for live transcription."
                    self.showPermissionAlert = true
                }
                completion(status == .authorized)
            }
        }
    }
    
    func hasAllPermissions() -> Bool {
        return microphoneStatus == .granted && speechStatus == .authorized
    }
    
    func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}
