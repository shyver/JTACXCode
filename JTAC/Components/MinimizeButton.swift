import SwiftUI

struct MinimizeButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }
            .foregroundColor(.white.opacity(0.7))
            .frame(width: 380, height: 80)
            .background(AppColors.minimizeButton)
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity)
    }
}	
