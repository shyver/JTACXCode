import SwiftUI
import SwiftData

struct DatabaseRootView: View {
    @Binding var currentView: AppScreen

    @State private var selectedCategory: DatabaseCategory = .assets

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(DatabaseCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                Group {
                    switch selectedCategory {
                    case .assets:
                        AssetsCallsignsListView()
                    case .airDefense:
                        AirDefenseListView()
                    case .reds:
                        RedsListView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Database")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        currentView = .home
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Home")
                        }
                        .foregroundColor(.white)
                    }
                }
            }
        }
        .tint(.white)
    }
}

enum DatabaseCategory: String, CaseIterable, Identifiable {
    case assets
    case airDefense
    case reds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assets: return "Assets & Callsigns"
        case .airDefense: return "AAA & SAMs"
        case .reds: return "REDs"
        }
    }
}
