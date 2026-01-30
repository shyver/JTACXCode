import AVFoundation
import SwiftUI

class MicrophonePermissionManager: ObservableObject {
    enum PermissionStatus {
        case undetermined
        case granted
        case denied
    }
    
    @Published var permissionStatus: PermissionStatus = .undetermined
    @Published var showPermissionDeniedAlert = false
    
    init() {
        checkPermission()
    }
    
    func checkPermission() {
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .undetermined:
            permissionStatus = .undetermined
        case .granted:
            permissionStatus = .granted
        case .denied:
            permissionStatus = .denied
        @unknown default:
            permissionStatus = .undetermined
        }
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