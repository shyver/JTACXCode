import SwiftUI
import SwiftData

struct AssetsCallsignsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\AssetCallsign.aircraft), SortDescriptor(\AssetCallsign.createdAt, order: .reverse)])
    private var assets: [AssetCallsign]

    @State private var showingAddSheet = false
    @State private var editingAsset: AssetCallsign?

    var body: some View {
        List {
            if assets.isEmpty {
                ContentUnavailableView("No assets", systemImage: "airplane", description: Text("Tap + to add an asset and its callsigns."))
                    .listRowBackground(Color.clear)
            }

            ForEach(assets) { asset in
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
                .swipeActions {
                    Button(role: .destructive) {
                        modelContext.delete(asset)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                }
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
                TextField("Aircraft", text: $asset.aircraft)
                TextField("AIR UNIT", value: $asset.airUnit, format: .number)
                    .keyboardType(.numberPad)

                Picker("Type", selection: $asset.typeRaw) {
                    ForEach(AssetType.allCases) { type in
                        Text(type.rawValue).tag(type.rawValue)
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
