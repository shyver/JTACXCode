import SwiftUI

@MainActor
class MainViewModel: ObservableObject {
    @Published var currentScreen: AppScreen = .main
    
    func navigateTo(_ screen: AppScreen) {
        withAnimation {
            currentScreen = screen
        }
    }
    
    func returnToMain() {
        withAnimation {
            currentScreen = .main
        }
    }
}
