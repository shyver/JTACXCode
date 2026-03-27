import SwiftUI
import SwiftData

struct AirDefenseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\AirDefenseSystem.name), SortDescriptor(\AirDefenseSystem.createdAt, order: .reverse)])
    private var systems: [AirDefenseSystem]

    @State private var showingAddSheet = false
    @State private var editingSystem: AirDefenseSystem?

    private var groupedSystems: [AirDefenseType: [AirDefenseSystem]] {
        Dictionary(grouping: systems, by: { $0.type })
    }

    var body: some View {
        ZStack {
            List {
                if systems.isEmpty {
                    ContentUnavailableView("No AAA & SAMs", systemImage: "shield", description: Text("Tap + to add an air defense system."))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(AirDefenseType.allCases) { type in
                        if let items = groupedSystems[type], !items.isEmpty {
                            Section {
                                ForEach(items) { system in
                                    Button {
                                        editingSystem = system
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(system.name.isEmpty ? "(Unnamed)" : system.name)
                                                .font(.headline)
                                                .foregroundColor(.white)

                                            HStack(spacing: 12) {
                                                Text(String(format: "Range: %.1f NM", system.maxEffectiveRangeNM))
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                                Text("Alt: \(system.maxAltitudeFt) ft")
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                            }

                                            if !system.guidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                Text("Guidance: \(system.guidance)")
                                                    .font(.subheadline)
                                                    .foregroundColor(.white.opacity(0.9))
                                                    .lineLimit(1)
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
                        Text("Add System")
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
                AirDefenseEditView(system: AirDefenseSystem())
            }
        }
        .sheet(item: $editingSystem) { system in
            NavigationStack {
                AirDefenseEditView(system: system)
            }
        }
    }
}

private struct AirDefenseEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var system: AirDefenseSystem

    private var canSave: Bool {
        !system.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("AAA & SAM") {
                VStack(alignment: .leading) {
                    Text("NAME").font(.caption).foregroundColor(.secondary)
                    TextField("NAME", text: $system.name)
                }
                VStack(alignment: .leading) {
                    Text("Type").font(.caption).foregroundColor(.secondary)
                    Picker("Type", selection: $system.typeRaw) {
                        ForEach(AirDefenseType.allCases) { type in
                            Text(type.rawValue).tag(type.rawValue)
                        }
                    }
                }
                VStack(alignment: .leading) {
                    Text("Max Effective Range (NM)").font(.caption).foregroundColor(.secondary)
                    TextField("max effective range (NM)", value: $system.maxEffectiveRangeNM, format: .number)
                        .keyboardType(.decimalPad)
                }
                VStack(alignment: .leading) {
                    Text("Max Alt (ft)").font(.caption).foregroundColor(.secondary)
                    TextField("max alt (ft)", value: $system.maxAltitudeFt, format: .number)
                        .keyboardType(.numberPad)
                }
                VStack(alignment: .leading) {
                    Text("Guidance").font(.caption).foregroundColor(.secondary)
                    TextField("guidance", text: $system.guidance)
                }
            }
        }
        .navigationTitle("AAA & SAM")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    if system.modelContext == nil {
                        modelContext.insert(system)
                    }
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }
}
