import SwiftUI

struct NineLineView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var jtacViewModel: JTACViewModel
    @State private var selectedCategory: String = "9 Line"

    let categories = ["CAS", "S. UPDATE", "9 Line", "Remarks", "Restrictions", "BDA", "GamePlan"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                StatusBar(viewModel: viewModel)

                HStack(spacing: 0) {
                    // Left sidebar
                    VStack(spacing: 10) {
                        ForEach(categories, id: \.self) { category in
                            CategoryButton(
                                title: category,
                                isSelected: selectedCategory == category,
                                hasData: jtacViewModel.hasData(for: category)
                            ) {
                                selectedCategory = category
                            }
                        }
                        Spacer()
                    }
                    .frame(width: 220)
                    .background(AppColors.sidebarBackground)
                    .padding(.trailing, 10)

                    // Content area — bound to JTACReport
                    VStack(alignment: .leading, spacing: 20) {
                        Text(selectedCategory)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.top, 20)

                        ScrollView {
                            let text = jtacViewModel.content(for: selectedCategory)
                            if text.isEmpty {
                                Text("No data yet.\nStart recording to populate this section.")
                                    .font(.system(size: 18))
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(20)
                            } else {
                                Text(text)
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(20)
                            }
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
    var hasData: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if hasData {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(isSelected ? AppColors.selectedCategory : AppColors.categoryButton)
            .cornerRadius(8)
        }
        .padding(.horizontal, 10)
    }
}
