import SwiftUI

struct LiveTranscriptView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                StatusBar(viewModel: viewModel)
                
                VStack(alignment: .leading, spacing: 20) {
                    Text("Live Radio Transcript")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 15) {
                                // Live partial text currently being transcribed
                                if !viewModel.liveTranscript.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(Color.red)
                                                .frame(width: 8, height: 8)
                                            Text("LIVE")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.red)
                                        }
                                        TranscriptMessage(text: viewModel.liveTranscript)
                                            .opacity(0.7)
                                    }
                                    .padding(8)
                                    .background(Color.blue.opacity(0.15))
                                    .cornerRadius(8)
                                }

                                // Completed segments from history, newest first
                                ForEach(viewModel.transcriptHistory.reversed()) { entry in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.timestamp, style: .time)
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                        TranscriptMessage(text: entry.text)
                                    }
                                }

                                // Placeholder when nothing yet
                                if viewModel.transcriptHistory.isEmpty && viewModel.liveTranscript.isEmpty {
                                    TranscriptMessage(text: "Press the record button to start transcribing...")
                                        .foregroundColor(.gray)
                                }

                                Color.clear.frame(height: 1).id("bottom")
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                        .onChange(of: viewModel.transcriptHistory.count) { _ in
                            withAnimation { proxy.scrollTo("bottom") }
                        }
                        .onChange(of: viewModel.liveTranscript) { _ in
                            withAnimation { proxy.scrollTo("bottom") }
                        }
                    }
                    .background(AppColors.transcriptBackground)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    
                    // Action buttons
                    HStack(spacing: 20) {
                        ActionButton(title: "Confirm", color: AppColors.confirmGreen)
                        ActionButton(title: "Correct", color: AppColors.correctYellow)
                        ActionButton(title: "Reject", color: AppColors.rejectRed)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    Spacer()
                    
                    MinimizeButton {
                        viewModel.returnToMain()
                    }
                    .padding(.bottom, 30)
                }
            }
        }
    }
}

struct TranscriptMessage: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 18))
            .foregroundColor(.white)
            .fixedSize(horizontal: false, vertical: true)
    }
}
