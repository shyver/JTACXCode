import SwiftUI

// NOTE: This is an older/simple version kept for reference. It is intentionally NOT named
// `NewMissionView` to avoid colliding with `JTAC/Views/NewMissionView.swift`.
struct LegacyNewMissionView: View {
    @Binding var currentView: AppScreen
    @State private var missionName: String = ""
    @State private var missionDetails: String = ""

    var body: some View {
        VStack {
            Text("New Mission")
                .font(.largeTitle)
                .padding(.bottom, 20)

            TextField("Mission Name", text: $missionName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            TextField("Mission Details", text: $missionDetails)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button(action: {
                // Logic to save mission data
                currentView = .main
            }) {
                Text("Start Mission")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}

struct LegacyNewMissionView_Previews: PreviewProvider {
    static var previews: some View {
        LegacyNewMissionView(currentView: .constant(.newMission))
    }
}
