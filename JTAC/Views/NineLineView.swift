import SwiftUI

struct NineLineView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var selectedCategory: String = "9 Line"
    
    let categories = ["CAS", "S. UPDATE", "9 Line", "Remarks", "Restrictions", "BDA", "GamePlan"]
    
    let nineLineContent = """
Line 1: IP Hammer.
Line 2: Heading 270.
Line 3: 8 decimal 5 miles.
Line 4: Target elevation 1450 feet.
Line 5: 2 BMPs in the open, grid 32S NB 43821 76219.
Line 6: Mark by red smoke.	
Line 7: Friendlies 400 meters south.
Line 8: Egress east.
Line 9: Remarks and restrictions, danger close, final attack heading 260 to 300.
"""
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                StatusBar()
                
                HStack(spacing: 0) {
                    // Left sidebar
                    VStack(spacing: 10) {
                        ForEach(categories, id: \.self) { category in
                            CategoryButton(
                                title: category,
                                isSelected: selectedCategory == category
                            ) {
                                selectedCategory = category
                            }
                        }
                        Spacer()
                    }
                    .frame(width: 220)
                    .background(AppColors.sidebarBackground)
                    .padding(.trailing, 10)
                    
                    // Content area
                    VStack(alignment: .leading, spacing: 20) {
                        Text(selectedCategory)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.top, 20)
                        
                        ScrollView {
                            Text(nineLineContent)
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                        }
                        .background(AppColors.transcriptBackground)
                        .cornerRadius(12)
                        
                        Spacer()
                        
                        MinimizeButton {
                            viewModel.returnToMain()
                        }
                        .padding(.bottom, 30)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(isSelected ? AppColors.selectedCategory : AppColors.categoryButton)
                .cornerRadius(8)
        }
        .padding(.horizontal, 10)
    }
}
