import SwiftUI
import SwiftData

struct RedsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\RedWeapon.weapon), SortDescriptor(\RedWeapon.createdAt, order: .reverse)])
    private var weapons: [RedWeapon]

    @State private var showingAddSheet = false
    @State private var editingWeapon: RedWeapon?

    var body: some View {
        List {
            if weapons.isEmpty {
                ContentUnavailableView("No RED entries", systemImage: "scope", description: Text("Tap + to add a weapon and its radii."))
                    .listRowBackground(Color.clear)
            }

            ForEach(weapons) { weapon in
                Button {
                    editingWeapon = weapon
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(weapon.weapon.isEmpty ? "(Unnamed Weapon)" : weapon.weapon)
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("Lethal \(weapon.lethalRadiusFt) • Frag \(weapon.fragRadiusFt) • DC \(weapon.dangerCloseFt) • Min Safe \(weapon.minSafeTroopsOpenFt) (ft)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.black.opacity(0.25))
                .swipeActions {
                    Button(role: .destructive) {
                        modelContext.delete(weapon)
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
                RedWeaponEditView(weapon: RedWeapon())
            }
        }
        .sheet(item: $editingWeapon) { weapon in
            NavigationStack {
                RedWeaponEditView(weapon: weapon)
            }
        }
    }
}

private struct RedWeaponEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var weapon: RedWeapon

    private var canSave: Bool {
        !weapon.weapon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("REDs") {
                TextField("WEAPON", text: $weapon.weapon)
                TextField("LETHAL RADIUS (ft)", value: $weapon.lethalRadiusFt, format: .number)
                    .keyboardType(.numberPad)
                TextField("FRAG RADIUS (ft)", value: $weapon.fragRadiusFt, format: .number)
                    .keyboardType(.numberPad)
                TextField("DANGER CLOSE (ft)", value: $weapon.dangerCloseFt, format: .number)
                    .keyboardType(.numberPad)
                TextField("MIN SAFE (troops open) (ft)", value: $weapon.minSafeTroopsOpenFt, format: .number)
                    .keyboardType(.numberPad)
            }
        }
        .navigationTitle("RED")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    if weapon.modelContext == nil {
                        modelContext.insert(weapon)
                    }
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }
}
