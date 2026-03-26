import SwiftUI

struct NewMissionView: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var currentView: AppScreen

    // Mission Details
    @State private var campaignMissionName: String = ""
    @State private var authentication: String = ""

    // CAS Check-in
    @State private var callsign: String = ""
    @State private var jtacCallsign: String = ""
    @State private var playTime: String = ""
    @State private var capabilities: String = ""
    @State private var laserCode: String = ""
    @State private var vdlCode: String = ""
    @State private var abortCode: String = ""

    // Aircraft Type
    @State private var selectedAircraftType: String = "A-10"
    let aircraftTypes = ["A-10", "F-16", "F-18", "F-35", "AC-130", "MQ-9"]

    // Frequencies
    @State private var primaryFreq: String = ""
    @State private var guardFreq: String = ""
    @State private var jtacFreq: String = ""

    // Ordnance Loadout
    @State private var selectedOrdnance: String = "Rockets"
    @State private var selectedOrdnances: [String] = []
    let ordnanceTypes = [
        "Rockets", "Gun", "Missiles", "Air to ground missiles",
        "MK-82", "MK-83", "MK-84",
        "GBU-10", "GBU-12", "GBU-16",
        "Hydra 70", "APKWS", "AGM-114 Hellfire", "AGM-65 Maverick",
        "AGM-88 HARM", "GBU-31", "GBU-38", "GBU-32"
    ]

    // SPINS Notes
    @State private var geometryPoints: [GeometryPoint] = []
    @State private var friendlyForces: [FriendlyForce] = []
    @State private var otherAssets: [OtherAsset] = []

    @State private var showAbortMissionSetupAlert: Bool = false

    /// Prevents repeatedly overwriting in-progress edits when the view re-appears.
    @State private var hasLoadedFromMissionData: Bool = false

#if DEBUG
    private let debugInstanceID = UUID().uuidString
    @State private var debugTouchCount: Int = 0
#endif

    var body: some View {
        NavigationStack {
            Form {
                // A tiny, non-interactive UIKit view embedded *inside* the Form's content.
                // This makes it reliable to find the underlying UITableView/UIScrollView.
                FormScrollConfigurator()
                    .frame(width: 1, height: 1)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .allowsHitTesting(false)

                Section {
                    TextField("Campaign/Mission Name", text: $campaignMissionName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Mission")
                }

                Section {
                    TextField("AUTHENTICATION", text: $authentication)
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("Authentication")
                }

                Section {
                    TextField("CALLSIGN", text: $callsign)
                    TextField("JTAC CALLSIGN", text: $jtacCallsign)
                    TextField("PLAY TIME", text: $playTime)
                    TextField("CAPABILITIES", text: $capabilities)
                    TextField("LASER CODE", text: $laserCode)
                    TextField("VDL CODE", text: $vdlCode)
                    TextField("ABORT CODE", text: $abortCode)
                } header: {
                    Text("CAS Check-in")
                }

                Section {
                    Picker("Aircraft", selection: $selectedAircraftType) {
                        ForEach(aircraftTypes, id: \.self) { Text($0) }
                    }
                } header: {
                    Text("Aircraft Type")
                }

                Section {
                    TextField("PRIMARY FREQ", text: $primaryFreq)
                    TextField("GUARD FREQ", text: $guardFreq)
                    TextField("JTAC FREQ", text: $jtacFreq)
                } header: {
                    Text("Frequencies")
                }

                Section {
                    Picker("Add Ordnance", selection: $selectedOrdnance) {
                        ForEach(ordnanceTypes, id: \.self) { Text($0) }
                    }

                    Button("Add") {
                        selectedOrdnances.append(selectedOrdnance)
                    }
                    .buttonStyle(.borderless)

                    if selectedOrdnances.isEmpty {
                        Text("No ordnance selected")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(selectedOrdnances.enumerated()), id: \.offset) { index, ord in
                            HStack {
                                Text(ord)
                                Spacer()
                                Button(role: .destructive) {
                                    selectedOrdnances.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                } header: {
                    Text("Ordnance Loadout")
                }

                Section {
                    // Using onTapGesture on row content instead of Button prevents the row
                    // from becoming a drag-intercepting full-width button inside Form.
                    Text("GEOMETRY (IPs, HOLDs, BPs, CPs)")
                        .foregroundColor(.white)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            geometryPoints.append(GeometryPoint())
                        }

                    Text("FRIENDLY FORCES (FLOT, FSCL, CFL, RFL)")
                        .foregroundColor(.white)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            friendlyForces.append(FriendlyForce())
                        }

                    Text("OTHER ASSETS IN AREA")
                        .foregroundColor(.white)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            otherAssets.append(OtherAsset())
                        }

                    if !geometryPoints.isEmpty {
                        ForEach($geometryPoints) { $point in
                            GeometryPointEditor(point: $point) {
                                if let idx = geometryPoints.firstIndex(where: { $0.id == point.id }) {
                                    geometryPoints.remove(at: idx)
                                }
                            }
                        }
                    }

                    if !friendlyForces.isEmpty {
                        ForEach($friendlyForces) { $force in
                            FriendlyForceEditor(force: $force) {
                                if let idx = friendlyForces.firstIndex(where: { $0.id == force.id }) {
                                    friendlyForces.remove(at: idx)
                                }
                            }
                        }
                    }

                    if !otherAssets.isEmpty {
                        ForEach($otherAssets) { $asset in
                            OtherAssetEditor(asset: $asset) {
                                if let idx = otherAssets.firstIndex(where: { $0.id == asset.id }) {
                                    otherAssets.remove(at: idx)
                                }
                            }
                        }
                    }
                } header: {
                    Text("SPINS Notes")
                }

                Section {
                    Button {
                        let casCheckin = CASCheckin(
                            callsign: callsign,
                            jtacCallsign: jtacCallsign,
                            playTime: playTime,
                            capabilities: capabilities,
                            laserCode: laserCode,
                            vdlCode: vdlCode,
                            abortCode: abortCode
                        )

                        let frequencies = Frequencies(
                            primary: primaryFreq,
                            guardFreq: guardFreq,
                            jtac: jtacFreq
                        )

                        let spinsNotes = SPINSNotes(
                            geometryPoints: geometryPoints,
                            friendlyForces: friendlyForces,
                            otherAssets: otherAssets
                        )

                        let missionData = MissionData(
                            campaignMissionName: campaignMissionName,
                            authentication: authentication,
                            casCheckin: casCheckin,
                            aircraftType: selectedAircraftType,
                            frequencies: frequencies,
                            ordnanceLoadout: selectedOrdnances.isEmpty ? [selectedOrdnance] : selectedOrdnances,
                            spinsNotes: spinsNotes
                        )

                        viewModel.missionData = missionData
                        currentView = .main
                    } label: {
                        Text("Start Mission")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Color.black.ignoresSafeArea())
            .foregroundColor(.white)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showAbortMissionSetupAlert = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.white)
                    }
                }
            }
            .alert("Abort mission setup?", isPresented: $showAbortMissionSetupAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Abort", role: .destructive) {
                    viewModel.missionData = nil
                    hasLoadedFromMissionData = false
                    currentView = .home
                }
            } message: {
                Text("Any entered mission details will be lost.")
            }
#if DEBUG
            .overlay(alignment: .topTrailing) {
                // Small, non-interactive debug badge showing this file is the active screen.
                Text("NM:\(debugInstanceID.prefix(4)) \(debugTouchCount)")
                    .font(.caption2)
                    .padding(6)
                    .background(.black.opacity(0.6))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(8)
                    .allowsHitTesting(false)
            }
#endif
        }
        .tint(.white)
        .onAppear {
            guard !hasLoadedFromMissionData else { return }
            guard let mission = viewModel.missionData else { return }

            // Only prefill if this screen is being revisited (or first time with existing data).
            campaignMissionName = mission.campaignMissionName
            authentication = mission.authentication

            callsign = mission.casCheckin.callsign
            jtacCallsign = mission.casCheckin.jtacCallsign
            playTime = mission.casCheckin.playTime
            capabilities = mission.casCheckin.capabilities
            laserCode = mission.casCheckin.laserCode
            vdlCode = mission.casCheckin.vdlCode
            abortCode = mission.casCheckin.abortCode

            selectedAircraftType = mission.aircraftType

            primaryFreq = mission.frequencies.primary
            guardFreq = mission.frequencies.guardFreq
            jtacFreq = mission.frequencies.jtac

            selectedOrdnances = mission.ordnanceLoadout
            // Keep the picker on a sensible value.
            if let first = mission.ordnanceLoadout.first {
                selectedOrdnance = first
            }

            geometryPoints = mission.spinsNotes.geometryPoints
            friendlyForces = mission.spinsNotes.friendlyForces
            otherAssets = mission.spinsNotes.otherAssets

            hasLoadedFromMissionData = true
        }
    }
}

private struct GeometryPointEditor: View {
    @Binding var point: GeometryPoint
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Geometry")
                    .font(.headline)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            Picker("TYPE", selection: $point.type) {
                ForEach(PointType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }

            TextField("Name", text: $point.name)
            TextField("Latitude", text: $point.latitude)
            TextField("Longitude", text: $point.longitude)
            TextField("Notes", text: $point.notes)
        }
        .padding(.vertical, 6)
    }
}

private struct FriendlyForceEditor: View {
    @Binding var force: FriendlyForce
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Friendly Force")
                    .font(.headline)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            Picker("TYPE", selection: $force.type) {
                ForEach(FriendlyForceType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }

            TextField("NAME / UNIT", text: $force.nameUnit)
            TextField("LAT", text: $force.latitude)
            TextField("LNG", text: $force.longitude)
            TextField("NOTES", text: $force.notes)
        }
        .padding(.vertical, 6)
    }
}

private struct OtherAssetEditor: View {
    @Binding var asset: OtherAsset
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Other Asset")
                    .font(.headline)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            TextField("ASSET", text: $asset.asset)
            TextField("TYPE", text: $asset.type)
            TextField("CALLSIGN", text: $asset.callsign)
            TextField("FREQ", text: $asset.freq)
            TextField("LAT", text: $asset.latitude)
            TextField("LNG", text: $asset.longitude)
            TextField("NOTES", text: $asset.notes)
        }
        .padding(.vertical, 6)
    }
}

struct NewMissionView_Previews: PreviewProvider {
    static var previews: some View {
        NewMissionView(viewModel: MainViewModel(), currentView: .constant(.newMission))
            .preferredColorScheme(.dark)
    }
}

/// Ensures the enclosing `UITableView`/`UIScrollView` used by `Form` is configured
/// to begin scrolling immediately (fixes delayed/laggy scroll that only works on fast swipes).
private struct FormScrollConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { apply(from: view) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { apply(from: uiView) }
    }

    private func apply(from view: UIView) {
        guard let scrollView = view.enclosingScrollViewInHierarchy else { return }

        // Core knobs that affect “slow swipe doesn’t scroll” behavior.
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.panGestureRecognizer.cancelsTouchesInView = true

        // SwiftUI-in-UIKit sometimes installs a private gesture recognizer that delays touches.
        // Disabling it often fixes the exact symptom: scroll works only when swiping fast.
        for gr in scrollView.gestureRecognizers ?? [] {
            let name = String(describing: type(of: gr))
            if name.contains("DelayedTouches") {
                gr.isEnabled = false
            }
        }

#if DEBUG
        // Diagnostics: these show up in the Xcode console so we can confirm attachment.
        let delayed = (scrollView.gestureRecognizers ?? []).map { String(describing: type(of: $0)) }.filter { $0.contains("DelayedTouches") }
        if !delayed.isEmpty {
            print("[ScrollFix] Disabled delayed recognizers:", delayed)
        }
        print("[ScrollFix] Attached to:", String(describing: type(of: scrollView)), "delaysContentTouches=", scrollView.delaysContentTouches)
#endif
    }
}

private extension UIView {
    /// Use both superview-walk and responder-chain walk; depending on SwiftUI layout,
    /// the actual UITableView may be reachable via either.
    var enclosingScrollViewInHierarchy: UIScrollView? {
        // 1) Superview chain
        var v: UIView? = self
        while let current = v {
            if let scroll = current as? UIScrollView { return scroll }
            v = current.superview
        }

        // 2) Next responder chain
        var r: UIResponder? = self
        while let current = r {
            if let scroll = current as? UIScrollView { return scroll }
            r = current.next
        }

        return nil
    }
}

// NOTE: The previous `FormPanScrollFix` implementation has been superseded by
// `FormScrollConfigurator` above because `.background` isn't guaranteed to be inside
// the UITableView used by `Form`.
