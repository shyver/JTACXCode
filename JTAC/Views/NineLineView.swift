import SwiftUI

struct NineLineView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var jtacViewModel: JTACViewModel

    private var selectedTabId: Binding<String> { $viewModel.selectedNineLineCategory }
    private var tabs: [NineLineTab] { NineLineTabs.all }

    private var selectedTab: NineLineTab {
        NineLineTabs.tab(for: selectedTabId.wrappedValue) ?? NineLineTabs.all.first!
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                StatusBar(viewModel: viewModel)

                HStack(spacing: 0) {
                    // Left sidebar
                    VStack(spacing: 10) {
                        ForEach(tabs) { tab in
                            CategoryButton(
                                title: tab.title,
                                isSelected: selectedTabId.wrappedValue == tab.id,
                                hasData: jtacViewModel.hasData(for: tab.jtacCategoryKey)
                            ) {
                                selectedTabId.wrappedValue = tab.id
                            }
                        }
                        Spacer()
                    }
                    .frame(width: 220)
                    .background(AppColors.sidebarBackground)
                    .padding(.trailing, 10)

                    // Content area — bound to selected tab
                    VStack(alignment: .leading, spacing: 20) {
                        Text(selectedTab.title)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.top, 20)

                        ScrollView {
                            // Determine content based on tab
                            if selectedTab.id == "authentication" {
                                let auth = viewModel.missionData?.authentication ?? ""
                                if auth.isEmpty {
                                    Text("No authentication set.")
                                        .font(.system(size: 18))
                                        .foregroundColor(.gray)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(20)
                                } else {
                                    Text(auth)
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(20)
                                }
                            } else if selectedTab.id == "casCheckIn" {
                                if let _ = viewModel.missionData {
                                    CASCheckinDetailView(viewModel: viewModel)
                                } else {
                                    Text("No CAS check-in data available.")
                                        .font(.system(size: 18))
                                        .foregroundColor(.gray)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(20)
                                }
                            } else if selectedTab.id == "nineLineBrief" {
                                NineLineBriefDetailView(jtacViewModel: jtacViewModel)
                            } else if selectedTab.id == "safetyOfFlight" {
                                SafetyOfFlightDetailView(jtacViewModel: jtacViewModel)
                            } else if selectedTab.id == "situationUpdate" {
                                SituationUpdateDetailView(jtacViewModel: jtacViewModel)
                            } else if selectedTab.id == "gamePlan" {
                                GamePlanDetailView(jtacViewModel: jtacViewModel)
                            } else if selectedTab.id == "remarks" {
                                RemarksDetailView(jtacViewModel: jtacViewModel)
                            } else if selectedTab.id == "restrictions" {
                                RestrictionsDetailView(jtacViewModel: jtacViewModel)
                            } else if selectedTab.id == "bda" {
                                BDADetailView(jtacViewModel: jtacViewModel)
                            } else {
                                let text = jtacViewModel.content(for: selectedTab.jtacCategoryKey)
                                if text.isEmpty {
                                    Text("No data yet.\nStart recording to populate this section.")
                                        .font(.system(size: 18))
                                        .foregroundColor(.gray)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(20)
                                } else {
                                    Text(text)
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(20)
                                }
                            }
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .background(AppColors.transcriptBackground)
                        .cornerRadius(12)

                        Spacer()

                        MinimizeButton {
                            viewModel.returnToMain()
                        }
                        .padding(.bottom, 30)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

struct CASCheckinDetailView: View {
    @ObservedObject var viewModel: MainViewModel
    var isCompact: Bool = false

    private var mission: MissionData? { viewModel.missionData }

    private var formattedOrdnance: String {
        let items = mission?.ordnanceLoadout ?? []
        guard !items.isEmpty else { return "—" }

        // Preserve the order items were added, but collapse duplicates into counts.
        var counts: [String: Int] = [:]
        var orderedUnique: [String] = []
        for item in items {
            if counts[item] == nil {
                orderedUnique.append(item)
                counts[item] = 1
            } else {
                counts[item, default: 0] += 1
            }
        }

        return orderedUnique
            .compactMap { name in
                let count = counts[name, default: 0]
                return count > 1 ? "\(count)x \(name)" : name
            }
            .joined(separator: ", ")
    }

    private var abortCodeBinding: Binding<String> {
        Binding(
            get: { viewModel.missionData?.casCheckin.abortCode ?? "" },
            set: { viewModel.updateAbortCode($0) }
        )
    }

    var body: some View {
        let checkin = mission?.casCheckin

        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            DetailRow(label: "CALLSIGN", value: checkin?.callsign ?? "", isCompact: isCompact)
            DetailRow(label: "MISSION", value: mission?.campaignMissionName ?? "", isCompact: isCompact)
            DetailRow(label: "AIRCRAFT TYPE", value: mission?.aircraftType ?? "", isCompact: isCompact)
            DetailRow(label: "POS & ALT", value: "", isCompact: isCompact)
            DetailRow(label: "ORDNANCE", value: formattedOrdnance, isCompact: isCompact)
            DetailRow(label: "PLAY TIME", value: checkin?.playTime ?? "", isCompact: isCompact)
            DetailRow(label: "CAPES", value: checkin?.capabilities ?? "", isCompact: isCompact)
            DetailRow(label: "LASER CODE", value: checkin?.laserCode ?? "", isCompact: isCompact)
            DetailRow(label: "VDL CODE", value: checkin?.vdlCode ?? "", isCompact: isCompact)

            // Editable: ABORT CODE
            EditableDetailRow(label: "ABORT CODE", text: abortCodeBinding, isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}

struct NineLineBriefDetailView: View {
    @ObservedObject var jtacViewModel: JTACViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<NineLine, String?>) -> Binding<String> {
        Binding(
            get: { jtacViewModel.report.nineLine?[keyPath: keyPath] ?? "" },
            set: { 
                if jtacViewModel.report.nineLine == nil { jtacViewModel.report.nineLine = NineLine() }
                jtacViewModel.report.nineLine?[keyPath: keyPath] = $0.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: "1. IP / BP", text: binding(for: \.ip), isCompact: isCompact)
            EditableDetailRow(label: "2. HDG", text: binding(for: \.heading), isCompact: isCompact)
            EditableDetailRow(label: "3. DISTANCE", text: binding(for: \.distance), isCompact: isCompact)
            EditableDetailRow(label: "4. ELEVATION", text: binding(for: \.targetElevation), isCompact: isCompact)
            EditableDetailRow(label: "5. TARGET", text: binding(for: \.targetDescription), isCompact: isCompact)
            EditableDetailRow(label: "6. LOCATION", text: binding(for: \.targetMark), isCompact: isCompact)
            EditableDetailRow(label: "7. MARK", text: binding(for: \.friendlies), isCompact: isCompact)
            EditableDetailRow(label: "8. FRIENDLIES", text: binding(for: \.egress), isCompact: isCompact)
            EditableDetailRow(label: "9. EGRESS", text: binding(for: \.remarksLine), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}

struct SafetyOfFlightDetailView: View {
    @ObservedObject var jtacViewModel: JTACViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<SafetyOfFlight, String?>) -> Binding<String> {
        Binding(
            get: { jtacViewModel.report.safetyOfFlight?[keyPath: keyPath] ?? "" },
            set: { 
                if jtacViewModel.report.safetyOfFlight == nil { jtacViewModel.report.safetyOfFlight = SafetyOfFlight() }
                jtacViewModel.report.safetyOfFlight?[keyPath: keyPath] = $0.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: "1. THREATS", text: binding(for: \.threats), isCompact: isCompact)
            EditableDetailRow(label: "2. FRIENDLY ASSETS", text: binding(for: \.friendlyAssets), isCompact: isCompact)
            EditableDetailRow(label: "3. TERRAINS AND OBSTACLES", text: binding(for: \.terrainsObstacles), isCompact: isCompact)
            EditableDetailRow(label: "4. EMERGENCY CONSIDERATIONS", text: binding(for: \.emergencyConsiderations), isCompact: isCompact)
            EditableDetailRow(label: "5. E POINT", text: binding(for: \.ePoint), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}

struct SituationUpdateDetailView: View {
    @ObservedObject var jtacViewModel: JTACViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<SituationUpdate, String?>) -> Binding<String> {
        Binding(
            get: { jtacViewModel.report.situationUpdate?[keyPath: keyPath] ?? "" },
            set: { 
                if jtacViewModel.report.situationUpdate == nil { jtacViewModel.report.situationUpdate = SituationUpdate() }
                jtacViewModel.report.situationUpdate?[keyPath: keyPath] = $0.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: "THREATS", text: binding(for: \.threats), isCompact: isCompact)
            EditableDetailRow(label: "TARGETS/ENEMY", text: binding(for: \.targets), isCompact: isCompact)
            EditableDetailRow(label: "FRIENDLIES", text: binding(for: \.friendlies), isCompact: isCompact)
            EditableDetailRow(label: "ARTY", text: binding(for: \.arty), isCompact: isCompact)
            EditableDetailRow(label: "CLEARANCE", text: binding(for: \.clearance), isCompact: isCompact)
            EditableDetailRow(label: "ORDNANCE", text: binding(for: \.ordnance), isCompact: isCompact)
            EditableDetailRow(label: "REMARKS/RESTRICTIONS", text: binding(for: \.remarks), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}

struct GamePlanDetailView: View {
    @ObservedObject var jtacViewModel: JTACViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<GamePlan, String?>) -> Binding<String> {
        Binding(
            get: { jtacViewModel.report.gamePlan?[keyPath: keyPath] ?? "" },
            set: { 
                if jtacViewModel.report.gamePlan == nil { jtacViewModel.report.gamePlan = GamePlan() }
                jtacViewModel.report.gamePlan?[keyPath: keyPath] = $0.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: "TYPE OF CONTROL", text: binding(for: \.typeOfControl), isCompact: isCompact)
            EditableDetailRow(label: "METHOD OF ATTACK", text: binding(for: \.methodOfAttack), isCompact: isCompact)
            EditableDetailRow(label: "GC INTENT", text: binding(for: \.gcIntent), isCompact: isCompact)
            EditableDetailRow(label: "CDE", text: binding(for: \.cde), isCompact: isCompact)
            EditableDetailRow(label: "ORDNANCE", text: binding(for: \.ordnance), isCompact: isCompact)
            EditableDetailRow(label: "DESIRED EFFECT", text: binding(for: \.desiredEffect), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}

struct RemarksDetailView: View {
    @ObservedObject var jtacViewModel: JTACViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<Remarks, String?>) -> Binding<String> {
        Binding(
            get: { jtacViewModel.report.remarks?[keyPath: keyPath] ?? "" },
            set: { 
                if jtacViewModel.report.remarks == nil { jtacViewModel.report.remarks = Remarks() }
                jtacViewModel.report.remarks?[keyPath: keyPath] = $0.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: "LASER TGT LINE", text: binding(for: \.laserTgtLine), isCompact: isCompact)
            EditableDetailRow(label: "PTL", text: binding(for: \.ptl), isCompact: isCompact)
            EditableDetailRow(label: "GUN-TGT-LINE(MAX ORD)", text: binding(for: \.gunTgtLine), isCompact: isCompact)
            EditableDetailRow(label: "MAX ORD", text: binding(for: \.maxOrd), isCompact: isCompact)
            EditableDetailRow(label: "OTHER", text: binding(for: \.text), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}

struct RestrictionsDetailView: View {
    @ObservedObject var jtacViewModel: JTACViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<Restrictions, String?>) -> Binding<String> {
        Binding(
            get: { jtacViewModel.report.restrictions?[keyPath: keyPath] ?? "" },
            set: { 
                if jtacViewModel.report.restrictions == nil { jtacViewModel.report.restrictions = Restrictions() }
                jtacViewModel.report.restrictions?[keyPath: keyPath] = $0.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: "DANGER CLOSE", text: binding(for: \.dangerClose), isCompact: isCompact)
            EditableDetailRow(label: "FAH", text: binding(for: \.fah), isCompact: isCompact)
            EditableDetailRow(label: "ACA’s", text: binding(for: \.acas), isCompact: isCompact)
            EditableDetailRow(label: "TOT/TTT", text: binding(for: \.totTtt), isCompact: isCompact)
            EditableDetailRow(label: "Lat/Alt", text: binding(for: \.latAlt), isCompact: isCompact)
            EditableDetailRow(label: "POST LAUNCH ABORT", text: binding(for: \.postLaunchAbort), isCompact: isCompact)
            EditableDetailRow(label: "OTHER", text: binding(for: \.text), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}

struct BDADetailView: View {
    @ObservedObject var jtacViewModel: JTACViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<BDAData, String?>) -> Binding<String> {
        Binding(
            get: { jtacViewModel.report.bda?[keyPath: keyPath] ?? "" },
            set: { 
                if jtacViewModel.report.bda == nil { jtacViewModel.report.bda = BDAData() }
                jtacViewModel.report.bda?[keyPath: keyPath] = $0.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: "STATUS", text: binding(for: \.status), isCompact: isCompact)
            EditableDetailRow(label: "SIZE", text: binding(for: \.size), isCompact: isCompact)
            EditableDetailRow(label: "ACTIVITY", text: binding(for: \.activity), isCompact: isCompact)
            EditableDetailRow(label: "LOCATION", text: binding(for: \.location), isCompact: isCompact)
            EditableDetailRow(label: "TIME", text: binding(for: \.time), isCompact: isCompact)
            EditableDetailRow(label: "REMARKS", text: binding(for: \.remarks), isCompact: isCompact)
            EditableDetailRow(label: "OTHER", text: binding(for: \.text), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}

struct EditableDetailRow: View {
    let label: String
    @Binding var text: String
    var isCompact: Bool = false

    var body: some View {
        if isCompact {
            HStack(alignment: .top) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.gray)
                    .frame(width: 110, alignment: .leading)

                TextField("—", text: $text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Text(label)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.gray)
                    .frame(width: 150, alignment: .leading)

                TextField("—", text: $text)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var isCompact: Bool = false

    var body: some View {
        if isCompact {
            HStack(alignment: .top) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.gray)
                    .frame(width: 110, alignment: .leading) // Fixed width for labels

                Text(value.isEmpty ? "—" : value)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Text(label)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.gray)
                    .frame(width: 150, alignment: .leading)

                Text(value.isEmpty ? "—" : value)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
        }
    }
}

struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    var hasData: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if hasData {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(isSelected ? AppColors.selectedCategory : AppColors.categoryButton)
            .cornerRadius(8)
        }
        .padding(.horizontal, 10)
    }
}
