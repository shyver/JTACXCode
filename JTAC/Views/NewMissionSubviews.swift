import SwiftUI

// MARK: - CAS Check-in Section View
struct CASCheckinSectionView: View {
    @Binding var callsign: String
    @Binding var jtacCallsign: String
    @Binding var playTime: String
    @Binding var capabilities: String
    @Binding var laserCode: String
    @Binding var vdlCode: String
    @Binding var abortCode: String

    var body: some View {
        Section(header: Text("CAS Check-in").font(.headline)) {
            VStack(spacing: 15) {
                TextField("CALLSIGN", text: $callsign)
                TextField("JTAC CALLSIGN", text: $jtacCallsign)
                TextField("PLAY TIME", text: $playTime)
                TextField("CAPABILITIES", text: $capabilities)
                TextField("LASER CODE", text: $laserCode)
                TextField("VDL CODE", text: $vdlCode)
                TextField("ABORT CODE", text: $abortCode)
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
        }
    }
}

// MARK: - Aircraft Type Section View
struct AircraftTypeSectionView: View {
    @Binding var selectedAircraftType: String
    let aircraftTypes: [String]

    var body: some View {
        Section(header: Text("Aircraft Type").font(.headline)) {
            Picker("Select Aircraft", selection: $selectedAircraftType) {
                ForEach(aircraftTypes, id: \.self) {
                    Text($0)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }
}

// MARK: - Frequencies Section View
struct FrequenciesSectionView: View {
    @Binding var primaryFreq: String
    @Binding var guardFreq: String
    @Binding var jtacFreq: String

    var body: some View {
        Section(header: Text("Frequencies").font(.headline)) {
            VStack(spacing: 15) {
                TextField("PRIMARY FREQ", text: $primaryFreq)
                TextField("GUARD FREQ", text: $guardFreq)
                TextField("JTAC FREQ", text: $jtacFreq)
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
        }
    }
}

// MARK: - Ordnance Loadout Section View
struct OrdnanceLoadoutSectionView: View {
    @Binding var ordnanceLoadout: [String]
    let ordnanceTypes: [String]
    
    @State private var ordnanceToAdd: String = "Rockets"

    var body: some View {
        Section(header: Text("Ordnance Loadout").font(.headline)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Add Ordnance", selection: $ordnanceToAdd) {
                        ForEach(ordnanceTypes, id: \.self) { Text($0) }
                    }
                    .pickerStyle(MenuPickerStyle())

                    Button("Add") {
                        ordnanceLoadout.append(ordnanceToAdd)
                    }
                    .buttonStyle(.bordered)
                }

                if ordnanceLoadout.isEmpty {
                    Text("No ordnance selected")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(ordnanceLoadout.indices, id: \.self) { index in
                            HStack {
                                Text(ordnanceLoadout[index])
                                Spacer()
                                Button(action: { ordnanceLoadout.remove(at: index) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                }
            }
        }
    }
}
