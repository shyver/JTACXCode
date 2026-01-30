import AVFoundation
import Speech
import SwiftUI

class PermissionManager: ObservableObject {
    @Published var microphoneStatus: AVAudioSession.RecordPermission = .undetermined
    @Published var speechStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var showPermissionAlert = false
    @Published var permissionAlertMessage = ""
    
    init() {
        checkPermissions()
    }
    
    func checkPermissions() {
        microphoneStatus = AVAudioSession.sharedInstance().recordPermission
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
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
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
