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
    @State private var currentScreen: AppScreen = .home

    // Keep local AppScreen in sync with MainViewModel navigation (tap-to-expand).
    private func syncScreenFromViewModel() {
        // Don’t override the onboarding flow screens.
        guard currentScreen != .home && currentScreen != .newMission else { return }

        switch viewModel.currentView {
        case .main:
            currentScreen = .main
        case .liveTranscript:
            currentScreen = .liveTranscript
        case .nineLine:
            currentScreen = .nineLine
        case .map:
            currentScreen = .map
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Main navigation container
            Group {
                switch currentScreen {
                case .home:
                    HomeView(currentView: $currentScreen)
                case .newMission:
                    NewMissionView(viewModel: viewModel, currentView: $currentScreen)
                case .main:
                    MainView(viewModel: viewModel)
                        .transition(.opacity)
                case .liveTranscript:
                    LiveTranscriptView(viewModel: viewModel)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .nineLine:
                    NineLineView(viewModel: viewModel, jtacViewModel: viewModel.jtacViewModel)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .map:
                    MapView(viewModel: viewModel)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .database:
                    Text("Database")
                        .foregroundColor(.white)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            // When ViewModel navigation changes, reflect it in the top-level screen.
            .onChange(of: viewModel.currentView) { _, _ in
                syncScreenFromViewModel()
            }
            // When StatusBar requests returning to Home, honor it here.
            .onChange(of: viewModel.shouldReturnToHome) { _, shouldReturn in
                guard shouldReturn else { return }
                currentScreen = .home
                viewModel.consumeReturnToHomeRequest()
            }
            // When StatusBar requests returning to New Mission, honor it here.
            .onChange(of: viewModel.shouldReturnToNewMission) { _, shouldReturn in
                guard shouldReturn else { return }
                currentScreen = .newMission
                viewModel.consumeReturnToNewMissionRequest()
            }
            // When switching to .main via the New Mission flow, ensure the VM matches.
            .onChange(of: currentScreen) { _, newValue in
                if newValue == .main {
                    viewModel.currentView = .main
                }
            }
        }
    }
}
