import SwiftUI

struct StatusBar: View {
    var body: some View {
        HStack {
            // GPS indicator
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundColor(.white)
                Text("GPS")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Recording indicator
            HStack(spacing: 8) {
                Text("Recording")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Circle()
                    .fill(Color.red)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(Color.black)
    }
}
