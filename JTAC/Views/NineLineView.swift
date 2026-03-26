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
                            if selectedTab.id == "authentication" {
                                let auth = viewModel.missionData?.authentication.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
