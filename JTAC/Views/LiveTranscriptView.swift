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
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            TranscriptMessage(text: "Axeman two-one this is Hawg one-one checking in, two by GBU-12, 30 mike-mike, playtime fifteen, fuel six point two.")
                            TranscriptMessage(text: "Hawg one-one roger, standby for tasking.")
                            TranscriptMessage(text: "...break...")
                            TranscriptMessage(text: "Hawg one-one type one control, troops in contact, grid three two Sierra November Bravo four three eight two one seven six two one nine, mark red smoke, say when tally.")
                            TranscriptMessage(text: "Tally smoke.")
                            TranscriptMessage(text: "Friendlies south four hundred meters, danger close, request immediate.")
                            TranscriptMessage(text: "Copy danger close, heading two seven zero, in hot.")
                            TranscriptMessage(text: "Cleared hot cleared hot.")
                            TranscriptMessage(text: "Rifle.")
                            TranscriptMessage(text: "Splash.")
                            TranscriptMessage(text: "Good hit good hit, one vehicle destroyed, second moving north.")
                            TranscriptMessage(text: "Copy, re-attack same grid.")
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
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
