import SwiftUI

struct HomeView: View {
    @Binding var currentView: AppScreen
    
    var body: some View {
        VStack(spacing: 20) {
            Text("RT-CAS")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.7))
                .padding(.bottom, 270)
            
            Button(action: {
                currentView = .newMission
            }) {
                Text("New Mission")
                    .frame(minWidth: 0, maxWidth: .infinity,
                           minHeight: 50)
                    .padding()
                    .background(Color.gray.opacity(0.9))
                    .foregroundColor(.white)
                    .cornerRadius(10).font(.title)
            }
            
            Button(action: {
                currentView = .database
            }) {
                Text("Database")
                    .frame(minWidth: 0, maxWidth: .infinity,
                           minHeight: 50)
                    .padding()
                    .background(Color.gray.opacity(0.9))
                    .foregroundColor(.white)
                    .cornerRadius(10).font(.title)
            }
            
            Button(action: {
                // Action for Archive
            }) {
                Text("Archive")
                    .frame(minWidth: 0, maxWidth: .infinity,
                           minHeight: 50)
                    .padding()
                    .background(Color.gray.opacity(0.9))
                    .foregroundColor(.white)
                    .cornerRadius(10).font(.title)
            }
            
            Button(action: {
                // Action for Settings
            }) {
                Text("Settings")
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 50)
                    .padding()
                    .background(Color.gray.opacity(0.9))
                    .foregroundColor(.white)
                    .cornerRadius(10).font(.title)
            }
            Spacer()
            Text("THIS APP IS CANNOT BE USED AS PRIMARY COMMUNICATION OR NAVIGATION TOOL")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Image("cover")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea().opacity(0.6)
        )
        
    }
    
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(currentView: .constant(.home))
    }
}
