import SwiftUI
import SwiftData

struct ArchiveView: View {
    @Binding var currentView: AppScreen
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \ArchivedMission.date, order: .reverse) private var archivedMissions: [ArchivedMission]
    
    @State private var selectedMission: ArchivedMission?
    
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
                
                Text("Archive")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Placeholder
                Text("Back")
                    .font(.system(size: 18, weight: .bold))
                    .opacity(0)
            }
            .padding()
            .background(Color(white: 0.15))
            
            if archivedMissions.isEmpty {
                Spacer()
                Text("No archived missions yet.")
                    .foregroundColor(.gray)
                    .font(.title3)
                Spacer()
            } else {
                List {
                    ForEach(archivedMissions) { mission in
                        Button(action: {
                            selectedMission = mission
                        }) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(mission.name.isEmpty ? "Unnamed Mission" : mission.name)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text(mission.date, style: .date)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        .listRowBackground(Color(white: 0.15))
                    }
                    .onDelete(perform: deleteMissions)
                }
                .scrollContentBackground(.hidden)
                .background(Color.black)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(item: $selectedMission) { mission in
            ArchivedMissionDetailView(mission: mission)
        }
    }
    
    private func deleteMissions(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(archivedMissions[index])
            }
        }
    }
}
