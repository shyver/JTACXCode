import SwiftUI
import SwiftData

struct AssetsCallsignsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\AssetCallsign.aircraft), SortDescriptor(\AssetCallsign.createdAt, order: .reverse)])
    private var assets: [AssetCallsign]

    @State private var showingAddSheet = false
    @State private var editingAsset: AssetCallsign?

    private var groupedAssets: [AssetType: [AssetCallsign]] {
        Dictionary(grouping: assets, by: { $0.type })
    }

    var body: some View {
        ZStack {
            List {
                if assets.isEmpty {
                    ContentUnavailableView("No assets", systemImage: "airplane", description: Text("Tap + to add an asset and its callsigns."))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(AssetType.allCases) { type in
                        if let items = groupedAssets[type], !items.isEmpty {
                            Section {
                                ForEach(items) { asset in
                                    Button {
                                        editingAsset = asset
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(asset.aircraft.isEmpty ? "(Unnamed Aircraft)" : asset.aircraft)
                                                    .font(.headline)
                                                    .foregroundColor(.white)
                                                Spacer()
                                                Text(asset.type.rawValue)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }

                                            HStack(spacing: 10) {
                                                Text("AIR UNIT: \(asset.airUnit)")
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                                if !asset.callsigns.isEmpty {
                                                    Text(asset.callsigns.joined(separator: ", "))
                                                        .font(.subheadline)
                                                        .foregroundColor(.white.opacity(0.9))
                                                        .lineLimit(1)
                                                }
                                            }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Color.black.opacity(0.25))
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        modelContext.delete(items[index])
                                    }
                                }
                            } header: {
                                Text(type.rawValue)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.3))
                                    .textCase(nil)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            
            VStack {
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Asset")
                    }
                    .font(.title2.weight(.bold))
                    .padding(.vertical, 14)
                    .padding(.horizontal, 24)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(radius: 4)
                }
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NavigationStack {
                AssetCallsignEditView(asset: AssetCallsign())
            }
        }
        .sheet(item: $editingAsset) { asset in
            NavigationStack {
                AssetCallsignEditView(asset: asset)
            }
        }
    }
}

private struct AssetCallsignEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var asset: AssetCallsign

    @State private var newCallsign: String = ""

    private var canSave: Bool {
        !asset.aircraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Asset") {
                VStack(alignment: .leading) {
                    Text("Aircraft").font(.caption).foregroundColor(.secondary)
                    TextField("Aircraft", text: $asset.aircraft)
                }
                VStack(alignment: .leading) {
                    Text("AIR UNIT").font(.caption).foregroundColor(.secondary)
                    TextField("AIR UNIT", value: $asset.airUnit, format: .number)
                        .keyboardType(.numberPad)
                }

                VStack(alignment: .leading) {
                    Text("Type").font(.caption).foregroundColor(.secondary)
                    Picker("Type", selection: $asset.typeRaw) {
                        ForEach(AssetType.allCases) { type in
                            Text(type.rawValue).tag(type.rawValue)
                        }
                    }
                }
            }

            Section("Callsigns") {
                HStack {
                    TextField("Add callsign", text: $newCallsign)
                        .textInputAutocapitalization(.characters)
                    Button("Add") {
                        let cs = newCallsign.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cs.isEmpty else { return }
                        asset.callsigns.append(cs)
                        newCallsign = ""
                    }
                    .buttonStyle(.borderless)
                }

                if asset.callsigns.isEmpty {
                    Text("No callsigns")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(asset.callsigns.enumerated()), id: \.offset) { idx, cs in
                        HStack {
                            Text(cs)
                            Spacer()
                            Button(role: .destructive) {
                                asset.callsigns.remove(at: idx)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .navigationTitle("Asset")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    // If this is a new object not yet inserted, insert it.
                    if asset.modelContext == nil {
                        modelContext.insert(asset)
                    }
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }
}
