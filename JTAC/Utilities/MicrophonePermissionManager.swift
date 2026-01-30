import AVFoundation
import SwiftUI

class MicrophonePermissionManager: ObservableObject {
    @Published var permissionStatus: AVAudioApplication.RecordPermission = .undetermined
    @Published var showPermissionDeniedAlert = false
    
    init() {
        checkPermission()
    }
    
    func checkPermission() {
        permissionStatus = AVAudioApplication.shared.recordPermission
    }
    
    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
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