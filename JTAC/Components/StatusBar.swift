import SwiftUI

struct StatusBar: View {
    @ObservedObject var viewModel: MainViewModel

    private var authenticationText: String? {
        let auth = viewModel.missionData?.authentication.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return auth.isEmpty ? nil : auth
    }

    var body: some View {
        HStack {
            // Back to main menu
            Button(action: {
                viewModel.requestReturnToNewMission()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                    Text("Menu")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Center: Authentication
            if let auth = authenticationText {
                Text(auth)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            } else {
                // Keep center space reserved so layout doesn't jump by using an empty Text view with the same font.
                Text("")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
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
