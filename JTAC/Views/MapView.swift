import SwiftUI

struct MapView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                StatusBar(viewModel: viewModel)
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    // MAP PLACEHOLDER - NO MapKit implementation
                    ZStack {
                        Color(red: 0.8, green: 0.8, blue: 0.8)
                        
                        VStack {
                            Image(systemName: "map")
                                .font(.system(size: 80))
                                .foregroundColor(.black.opacity(0.3))
                            
                            Text("Map Placeholder")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.black.opacity(0.5))
                                .padding(.top, 10)
                            
                            Text("Map component will be integrated here")
                                .font(.system(size: 16))
                                .foregroundColor(.black.opacity(0.4))
                        }
                        
                        // Navigation arrow icon (as shown in design)
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.height * 0.85)
                    
                    MinimizeButton {
                        viewModel.returnToMain()
                    }
                    .padding(.bottom, 30)
                }
            }
        }
    }
}
