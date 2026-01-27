import SwiftUI

struct MinimizeButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 24))
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 24))
            }
            .foregroundColor(.white.opacity(0.7))
            .frame(width: 380, height: 80)
            .background(AppColors.minimizeButton)
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity)
    }
}	
