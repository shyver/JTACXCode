import AVFoundation
import SwiftUI

class MicrophonePermissionManager: ObservableObject {
    @Published var permissionStatus: AVAudioSession.RecordPermission = .undetermined
    @Published var showPermissionDeniedAlert = false
    
    init() {
        checkPermission()
    }
    
    func checkPermission() {
        permissionStatus = AVAudioSession.sharedInstance().recordPermission
    }
    
    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.permissionStatus = granted ? .granted : .denied
                if !granted {
                    self.showPermissionDeniedAlert = true
                }
                completion(granted)
            }
        }
    }
    
    func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}