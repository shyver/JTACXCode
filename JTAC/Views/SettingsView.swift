import SwiftUI

struct SettingsView: View {
    @Binding var currentView: AppScreen
    @Environment(\.modelContext) private var modelContext
    
    @AppStorage("autoCapitalizeTranscripts") private var autoCapitalizeTranscripts: Bool = true
    @AppStorage("alertVolume") private var alertVolume: Double = 0.5
    
    @State private var showResetConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    currentView = .home
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                        Text("Back")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.white)
                }
                
                Spacer()
                
                Text("Settings")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Placeholder to balance the back button
                Text("Back")
                    .font(.system(size: 18, weight: .bold))
                    .opacity(0)
            }
            .padding()
            .background(Color(white: 0.15))
            
            // Settings List
            Form {
                Section(header: Text("Speech Recognition").foregroundColor(.gray)) {
                    Toggle("Auto-Capitalize Transcripts", isOn: $autoCapitalizeTranscripts)
                        .tint(.blue)
                }
                .listRowBackground(Color(white: 0.15))
                .foregroundColor(.white)
                
                Section(header: Text("Audio").foregroundColor(.gray)) {
                    VStack(alignment: .leading) {
                        Text("Alert Volume")
                        Slider(value: $alertVolume, in: 0...1) {
                            Text("Volume")
                        } minimumValueLabel: {
                            Image(systemName: "speaker.fill")
                        } maximumValueLabel: {
                            Image(systemName: "speaker.wave.3.fill")
                        }
                        .tint(.blue)
                    }
                }
                .listRowBackground(Color(white: 0.15))
                .foregroundColor(.white)
                
                Section(header: Text("Data Management").foregroundColor(.gray)) {
                    Button(action: {
                        showResetConfirmation = true
                    }) {
                        Text("Reset Default Database")
                            .foregroundColor(.red)
                    }
                }
                .listRowBackground(Color(white: 0.15))
                
                Section(header: Text("About").foregroundColor(.gray)) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                }
                .listRowBackground(Color(white: 0.15))
                .foregroundColor(.white)
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
        }
        .background(Color.black.ignoresSafeArea())
        .alert("Reset Database?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetDatabase()
            }
        } message: {
            Text("This will delete all custom entries and restore the factory default military assets, air defenses, and weapons. This action cannot be undone.")
        }
    }
    
    private func resetDatabase() {
        do {
            try modelContext.delete(model: AirDefenseSystem.self)
            try modelContext.delete(model: AssetCallsign.self)
            try modelContext.delete(model: RedWeapon.self)
            
            // Re-seed original data
            seedData(context: modelContext)
            
        } catch {
            print("Failed to reset database: \(error)")
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(currentView: .constant(.settings))
    }
}
