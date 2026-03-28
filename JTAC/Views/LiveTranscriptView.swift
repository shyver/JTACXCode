import SwiftUI

struct LiveTranscriptView: View {
    @ObservedObject var viewModel: MainViewModel

    // Limit how many history entries we render to keep scrolling smooth.
    private let maxHistoryEntries: Int = 200

    private var displayedHistory: [MainViewModel.TranscriptEntry] {
        // Keep chronological order (oldest -> newest) for stable rendering.
        // Only keep the last N entries.
        Array(viewModel.transcriptHistory.suffix(maxHistoryEntries))
    }

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
                            LazyVStack(alignment: .leading, spacing: 15) {
                                // Completed segments from history (chronological)
                                ForEach(displayedHistory) { entry in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.timestamp, style: .time)
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                        TranscriptMessage(text: entry.text)
                                    }
                                }

                                // Live partial text currently being transcribed (always at bottom)
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

                                // Placeholder when nothing yet
                                if displayedHistory.isEmpty && viewModel.liveTranscript.isEmpty {
                                    TranscriptMessage(text: "Press the record button to start transcribing...")
                                        .foregroundColor(.gray)
                                }

                                Color.clear.frame(height: 1).id("bottom")
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: viewModel.transcriptHistory.count) { _, _ in
                            // Avoid animation during continuous updates; it can cause stutter.
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                        .onChange(of: viewModel.liveTranscript) { _, _ in
                            proxy.scrollTo("bottom", anchor: .bottom)
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
    @AppStorage("autoCapitalizeTranscripts") private var autoCapitalize: Bool = true

    var body: some View {
        Text(autoCapitalize ? text.uppercased() : text)
            .font(.system(size: 18))
            .foregroundColor(.white)
            .fixedSize(horizontal: false, vertical: true)
    }
}
