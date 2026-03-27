import SwiftUI
import SwiftData

struct AirDefenseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\AirDefenseSystem.name), SortDescriptor(\AirDefenseSystem.createdAt, order: .reverse)])
    private var systems: [AirDefenseSystem]

    @State private var showingAddSheet = false
    @State private var editingSystem: AirDefenseSystem?

    var body: some View {
        List {
            if systems.isEmpty {
                ContentUnavailableView("No AAA/SAM entries", systemImage: "dot.radiowaves.left.and.right", description: Text("Tap + to add a system."))
                    .listRowBackground(Color.clear)
            }

            ForEach(systems) { system in
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
                .swipeActions {
                    Button(role: .destructive) {
                        modelContext.delete(system)
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
