import SwiftUI
import SwiftData

struct RedsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\RedWeapon.weapon), SortDescriptor(\RedWeapon.createdAt, order: .reverse)])
    private var weapons: [RedWeapon]

    @State private var showingAddSheet = false
    @State private var editingWeapon: RedWeapon?

    var body: some View {
        ZStack {
            List {
                if weapons.isEmpty {
                    ContentUnavailableView("No REDs", systemImage: "exclamationmark.triangle", description: Text("Tap + to add a RED weapon."))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(RedWeaponType.allCases) { weaponType in
                        let filteredWeapons = weapons.filter { $0.type == weaponType }
                        
                        if !filteredWeapons.isEmpty {
                            Section {
                                ForEach(filteredWeapons) { weapon in
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
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        modelContext.delete(filteredWeapons[index])
                                    }
                                }
                            } header: {
                                Text(weaponType.rawValue)
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.3))
                                    .foregroundColor(.white)
                                    .listRowInsets(EdgeInsets())
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
                        Text("Add WEAPON RED")
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
                VStack(alignment: .leading) {
                    Text("WEAPON").font(.caption).foregroundColor(.secondary)
                    TextField("WEAPON", text: $weapon.weapon)
                }
                
                VStack(alignment: .leading) {
                    Text("TYPE").font(.caption).foregroundColor(.secondary)
                    Picker("TYPE", selection: $weapon.type) {
                        ForEach(RedWeaponType.allCases) { weaponType in
                            Text(weaponType.rawValue).tag(weaponType)
                        }
                    }
                }
                
                VStack(alignment: .leading) {
                    Text("LETHAL RADIUS (ft)").font(.caption).foregroundColor(.secondary)
                    TextField("LETHAL RADIUS (ft)", value: $weapon.lethalRadiusFt, format: .number)
                        .keyboardType(.numberPad)
                }
                VStack(alignment: .leading) {
                    Text("FRAG RADIUS (ft)").font(.caption).foregroundColor(.secondary)
                    TextField("FRAG RADIUS (ft)", value: $weapon.fragRadiusFt, format: .number)
                        .keyboardType(.numberPad)
                }
                VStack(alignment: .leading) {
                    Text("DANGER CLOSE (ft)").font(.caption).foregroundColor(.secondary)
                    TextField("DANGER CLOSE (ft)", value: $weapon.dangerCloseFt, format: .number)
                        .keyboardType(.numberPad)
                }
                VStack(alignment: .leading) {
                    Text("MIN SAFE (troops open) (ft)").font(.caption).foregroundColor(.secondary)
                    TextField("MIN SAFE (troops open) (ft)", value: $weapon.minSafeTroopsOpenFt, format: .number)
                        .keyboardType(.numberPad)
                }
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
