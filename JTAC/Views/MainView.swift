import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // StatusBar at the top
                StatusBar(viewModel: viewModel)
                
                
                // Top half: Live Transcript (left) + 9 Line (right)
                GeometryReader { geo in
                    let totalWidth = geo.size.width
                    let transcriptWidth = totalWidth * 0.45
                    let nineLineWidth = totalWidth - transcriptWidth

                    HStack(spacing: 0) {
                        // Live Radio Transcript Section (Top Left)
                        LiveTranscriptSection(viewModel: viewModel)
                            .frame(width: transcriptWidth)

                        // 9 Line Section (Top Right)
                        NineLineSection(viewModel: viewModel, jtacViewModel: viewModel.jtacViewModel)
                            .frame(width: nineLineWidth)
                    }
                }
                .frame(height: UIScreen.main.bounds.height * 0.5)
                
                // Bottom half: Map
                MapSection(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Live Transcript Section (Top Left)
struct LiveTranscriptSection: View {
    @ObservedObject var viewModel: MainViewModel

    private let maxHistoryEntries: Int = 80

    private var displayedHistory: [MainViewModel.TranscriptEntry] {
        Array(viewModel.transcriptHistory.suffix(maxHistoryEntries))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Live Radio Transcript")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Show recording indicator here too
                if viewModel.isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                        Text("LIVE")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 15)
            .padding(.bottom, 10)
            
            // Tappable transcript area
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    // Show transcript history (chronological)
                    ForEach(displayedHistory) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.timestamp, style: .time)
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            TranscriptLine(text: entry.text)
                        }
                    }

                    // Show live transcript if recording (at bottom)
                    if viewModel.isRecording && !viewModel.liveTranscript.isEmpty {
                        TranscriptLine(text: viewModel.liveTranscript)
                            .padding(8)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                    }

                    // Placeholder if nothing
                    if !viewModel.isRecording && displayedHistory.isEmpty {
                        TranscriptLine(text: "Press the record button to start transcribing...")
                            .foregroundColor(.gray)
                    }
                }
                .padding(15)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.transcriptBackground)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.navigateTo(.liveTranscript)
            }
            
            // Action buttons
            HStack(spacing: 10) {
                ActionButton(title: "Confirm", color: AppColors.confirmGreen)
                    .frame(height: 60)
                ActionButton(title: "Correct", color: AppColors.correctYellow)
                    .frame(height: 60)
                ActionButton(title: "Reject", color: AppColors.rejectRed)
                    .frame(height: 60)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
        }
        .background(Color.black)
    }
}

// MARK: - 9 Line Section (Top Right)
struct NineLineSection: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var jtacViewModel: JTACViewModel

    // Use shared selection so it persists when expanding.
    private var selectedTabId: Binding<String> { $viewModel.selectedNineLineCategory }

    private var tabs: [NineLineTab] { NineLineTabs.all }

    private var selectedTab: NineLineTab {
        NineLineTabs.tab(for: selectedTabId.wrappedValue) ?? NineLineTabs.all.first!
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar — category switcher, does NOT expand
            VStack(spacing: 6) {
                ForEach(tabs) { tab in
                    Button(action: { selectedTabId.wrappedValue = tab.id }) {
                        HStack {
                            Text(tab.shortTitle)
                                .font(.system(size: 13,
                                              weight: selectedTabId.wrappedValue == tab.id ? .semibold : .regular))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if jtacViewModel.hasData(for: tab.jtacCategoryKey) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                            }
                        }
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(selectedTabId.wrappedValue == tab.id
                                    ? AppColors.selectedCategory
                                    : AppColors.categoryButton)
                        .cornerRadius(6)
                    }
                    .padding(.horizontal, 6)
                }
                Spacer()
            }
            .frame(width: 90)
            .background(AppColors.sidebarBackground)

            // Right content area — tappable to expand
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedTab.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 10)
                    .padding(.horizontal, 8)

                ScrollView {
                    // Mission-driven sections
                    if selectedTab.id == "casCheckIn" || selectedTab.jtacCategoryKey == "CAS" {
                        if let _ = viewModel.missionData {
                            CASCheckinDetailView(viewModel: viewModel, isCompact: true)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 10)
                        } else {
                            Text("No CAS check-in data available.")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                    } else if selectedTab.id == "authentication" {
                        let auth = viewModel.missionData?.authentication.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if auth.isEmpty {
                            Text("No authentication set.")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        } else {
                            Text(auth)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                    } else {
                        let text = jtacViewModel.content(for: selectedTab.jtacCategoryKey)
                        if text.isEmpty {
                            NineLineText(text: "No data yet for \(selectedTab.title).")
                                .foregroundColor(.gray)
                                .padding(10)
                        } else {
                            Text(text)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                    }
                }
                .background(AppColors.transcriptBackground)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.navigateTo(.nineLine)
            }
        }
        .background(Color.black)
    }
}

// MARK: - Map Section (Bottom Half)
struct MapSection: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        Button(action: {
            viewModel.navigateTo(.map)
        }) {
            ZStack {
                // Map Placeholder
                Color(red: 0.8, green: 0.8, blue: 0.8)
                
                VStack {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.black)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Helper Views
struct TranscriptLine: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundColor(.white)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct NineLineText: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundColor(.white)
            .fixedSize(horizontal: false, vertical: true)
    }
}
