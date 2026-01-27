import SwiftUI

@main
struct MilitaryRadioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Main navigation container
            Group {
                switch viewModel.currentScreen {
                case .main:
                    MainView(viewModel: viewModel)
                        .transition(.opacity)
                case .liveTranscript:
                    LiveTranscriptView(viewModel: viewModel)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .nineLine:
                    NineLineView(viewModel: viewModel)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .map:
                    MapView(viewModel: viewModel)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentScreen)
        }
    }
}
