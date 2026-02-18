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
                HStack(spacing: 0) {
                    // Live Radio Transcript Section (Top Left)
                    LiveTranscriptSection(viewModel: viewModel)
                        .frame(maxWidth: .infinity)
                    
                    // 9 Line Section (Top Right)
                    NineLineSection(viewModel: viewModel, jtacViewModel: viewModel.jtacViewModel)
                        .frame(maxWidth: .infinity)
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
            Button(action: {
                viewModel.navigateTo(.liveTranscript)
            }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Show live transcript if recording
                        if viewModel.isRecording && !viewModel.liveTranscript.isEmpty {
                            TranscriptLine(text: viewModel.liveTranscript)
                                .padding(8)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                        }
                        
                        // Show transcript history
                        ForEach(viewModel.transcriptHistory.reversed()) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.timestamp, style: .time)
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                TranscriptLine(text: entry.text)
                            }
                        }
                        
                        // Placeholder if nothing
                        if !viewModel.isRecording && viewModel.transcriptHistory.isEmpty {
                            TranscriptLine(text: "Press the record button to start transcribing...")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(15)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.transcriptBackground)
            }
            .buttonStyle(PlainButtonStyle())
            
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
    @State private var selectedCategory: String = "9 Line"

    let categories = ["CAS", "S. UPDATE", "9 Line", "Remarks", "Restrictions", "BDA", "GamePlan"]

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar — category switcher, does NOT expand
            VStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    Button(action: { selectedCategory = category }) {
                        HStack {
                            Text(category)
                                .font(.system(size: 14,
                                              weight: selectedCategory == category ? .semibold : .regular))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if jtacViewModel.hasData(for: category) {
                                Circle().fill(Color.green).frame(width: 7, height: 7)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(selectedCategory == category
                                    ? AppColors.selectedCategory
                                    : AppColors.categoryButton)
                        .cornerRadius(6)
                    }
                    .padding(.horizontal, 8)
                }
                Spacer()
            }
            .frame(width: 140)
            .background(AppColors.sidebarBackground)

            // Right content area — tappable to expand, shows live report data
            Button(action: { viewModel.navigateTo(.nineLine) }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(selectedCategory)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 15)
                        .padding(.horizontal, 15)

                    let text = jtacViewModel.content(for: selectedCategory)
                    ScrollView {
                        if text.isEmpty {
                            NineLineText(text: "No data yet for \(selectedCategory).")
                                .foregroundColor(.gray)
                                .padding(15)
                        } else {
                            Text(text)
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(15)
                        }
                    }
                    .background(AppColors.transcriptBackground)
                    .padding(.horizontal, 15)
                    .padding(.bottom, 15)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(PlainButtonStyle())
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
