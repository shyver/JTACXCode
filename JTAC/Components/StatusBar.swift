import SwiftUI

struct StatusBar: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var isRecording = false
    
    var body: some View {
        HStack {
            // GPS indicator
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundColor(.white)
                Text("GPS")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Recording button
            Button(action: {
                handleRecordButtonTap()
            }) {
                HStack(spacing: 8) {
                    Text(isRecording ? "Recording" : "Record")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Circle()
                        .fill(isRecording ? Color.red : Color.gray)
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(Color.black)
        .alert("Microphone Access Denied", isPresented: $viewModel.microphoneManager.showPermissionDeniedAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Open Settings") {
                viewModel.microphoneManager.openSettings()
            }
        } message: {
            Text("Please enable microphone access in Settings to use recording features.")
        }
    }
    
    private func handleRecordButtonTap() {
        if isRecording {
            // Stop recording
            stopRecording()
        } else {
            // Check permission before starting
            switch viewModel.microphoneManager.permissionStatus {
            case .granted:
                startRecording()
            case .denied:
                viewModel.microphoneManager.showPermissionDeniedAlert = true
            case .undetermined:
                viewModel.microphoneManager.requestPermission { granted in
                    if granted {
                        startRecording()
                    }
                }
            }
        }
    }
    
    private func startRecording() {
        isRecording = true
        // TODO: Implement actual recording logic
    }
    
    private func stopRecording() {
        isRecording = false
        // TODO: Implement stop recording logic
    }
}
