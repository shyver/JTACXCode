import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                StatusBar()
                
                VStack(spacing: 30) {
                    Spacer()
                    
                    // Three section cards
                    SectionCard(
                        title: "Live Radio Transcript",
                        systemImage: "waveform",
                        color: .blue
                    ) {
                        viewModel.navigateTo(.liveTranscript)
                    }
                    
                    SectionCard(
                        title: "9 Line",
                        systemImage: "list.number",
                        color: .orange
                    ) {
                        viewModel.navigateTo(.nineLine)
                    }
                    
                    SectionCard(
                        title: "Map View",
                        systemImage: "map",
                        color: .green
                    ) {
                        viewModel.navigateTo(.map)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 40)
            }
        }
    }
}	
