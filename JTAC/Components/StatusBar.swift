import SwiftUI

struct StatusBar: View {
    @State private var isRecording = true
    
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
            
            // Recording button
            Button(action: {
                isRecording.toggle()
            }) {
                HStack(spacing: 8) {
                    Text(isRecording ? "Recording" : "Record")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(Color.black)
    }
}
