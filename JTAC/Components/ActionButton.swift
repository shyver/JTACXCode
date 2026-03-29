import SwiftUI

struct ActionButton: View {
    let title: String
    let color: Color
    var action: () -> Void = {}
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 70)
                .background(color)
                .cornerRadius(12)
        }
    }
}
