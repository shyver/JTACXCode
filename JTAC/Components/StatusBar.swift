import SwiftUI

struct StatusBar: View {
    @ObservedObject var viewModel: MainViewModel
    
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
                viewModel.toggleRecording()
            }) {
                HStack(spacing: 8) {
                    Text(viewModel.isRecording ? "Recording" : "Record")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Circle()
                        .fill(viewModel.isRecording ? Color.red : Color.gray)
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(Color.black)
        .alert(viewModel.permissionManager.permissionAlertMessage, isPresented: $viewModel.permissionManager.showPermissionAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Open Settings") {
                viewModel.permissionManager.openSettings()
            }
        } message: {
            Text("Please enable permissions in Settings to use this feature.")
        }
    }
}
