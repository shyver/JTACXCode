import SwiftUI

struct ArchivedMissionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let mission: ArchivedMission
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    if let mData = mission.missionData {
                        missionSetupSection(mData)
                    }
                    
                    if let report = mission.report {
                        reportSection(report)
                    }
                    
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(mission.name.isEmpty ? "Archived Mission" : mission.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .bold()
                }
            }
            // Add a proper dark theme background to the Nav stack
            .toolbarBackground(Color(white: 0.15), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
    
    @ViewBuilder
    private func missionSetupSection(_ data: MissionData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mission Setup")
                .font(.title2)
                .bold()
                .foregroundColor(.white)
            
            VBox {
                detailRow("Authentication", data.authentication)
                detailRow("Aircraft Type", data.aircraftType)
                detailRow("Ordnance Loadout", data.ordnanceLoadout.joined(separator: ", "))
            }
            
            Text("CAS Check-In")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 5)
            VBox {
                detailRow("Callsign", data.casCheckin.callsign)
                detailRow("JTAC", data.casCheckin.jtacCallsign)
                detailRow("Play Time", data.casCheckin.playTime)
                detailRow("Capes", data.casCheckin.capabilities)
                detailRow("Laser", data.casCheckin.laserCode)
                detailRow("VDL", data.casCheckin.vdlCode)
                detailRow("Abort", data.casCheckin.abortCode)
            }
            
            Text("Frequencies")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 5)
            VBox {
                detailRow("Primary", data.frequencies.primary)
                detailRow("Guard", data.frequencies.guardFreq)
                detailRow("JTAC", data.frequencies.jtac)
            }
        }
    }
    
    @ViewBuilder
    private func reportSection(_ report: JTACReport) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Extracted Report")
                .font(.title2)
                .bold()
                .foregroundColor(.white)
                .padding(.top, 10)
            
            if let sitrep = report.situationUpdate, !sitrep.isEmpty {
                Text("Situation Update")
                    .font(.headline)
                    .foregroundColor(.white)
                VBox {
                    detailRow("Threats", sitrep.threats)
                    detailRow("Targets", sitrep.targets)
                    detailRow("Friendlies", sitrep.friendlies)
                    detailRow("Arty", sitrep.arty)
                    detailRow("Clearance", sitrep.clearance)
                    detailRow("Ordnance", sitrep.ordnance)
                    detailRow("Remarks", sitrep.remarks)
                }
            }
            
            if let gamePlan = report.gamePlan, !gamePlan.isEmpty {
                Text("Game Plan")
                    .font(.headline)
                    .foregroundColor(.white)
                VBox {
                    detailRow("Control Type", gamePlan.typeOfControl)
                    detailRow("Method", gamePlan.methodOfAttack)
                    detailRow("Intent", gamePlan.gcIntent)
                    detailRow("CDE", gamePlan.cde)
                    detailRow("Ordnance", gamePlan.ordnance)
                    detailRow("Effect", gamePlan.desiredEffect)
                }
            }
            
            if let safety = report.safetyOfFlight, !safety.isEmpty {
                Text("Safety of Flight")
                    .font(.headline)
                    .foregroundColor(.white)
                VBox {
                    detailRow("Threats", safety.threats)
                    detailRow("Friendly Assets", safety.friendlyAssets)
                    detailRow("Terrain", safety.terrainsObstacles)
                    detailRow("Emergencies", safety.emergencyConsiderations)
                    detailRow("E Point", safety.ePoint)
                }
            }
            
            if let nineLine = report.nineLine {
                Text("9-Line Brief")
                    .font(.headline)
                    .foregroundColor(.white)
                VBox {
                    detailRow("1. IP", nineLine.ip)
                    detailRow("2. Heading", nineLine.heading)
                    detailRow("3. Distance", nineLine.distance)
                    detailRow("4. Elevation", nineLine.targetElevation)
                    detailRow("5. Description", nineLine.targetDescription)
                    detailRow("6. Mark", nineLine.targetMark)
                    detailRow("7. Friendlies", nineLine.friendlies)
                    detailRow("8. Egress", nineLine.egress)
                    detailRow("9. Remarks", nineLine.remarksLine)
                }
            }
            
            if let bda = report.bda, !bda.isEmpty {
                Text("BDA")
                    .font(.headline)
                    .foregroundColor(.white)
                VBox {
                    detailRow("Status", bda.status)
                    detailRow("Size", bda.size)
                    detailRow("Activity", bda.activity)
                    detailRow("Location", bda.location)
                    detailRow("Time", bda.time)
                    detailRow("Remarks", bda.remarks)
                    detailRow("Other", bda.text)
                }
            }
        }
    }
    
    private func detailRow(_ label: String, _ value: String?) -> some View {
        Group {
            if let text = value, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .top) {
                    Text(label + ":")
                        .foregroundColor(.gray)
                        .frame(width: 100, alignment: .leading)
                    Text(text)
                        .foregroundColor(.white)
                }
            }
        }
    }
}

private struct VBox<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.12))
        .cornerRadius(8)
    }
}
