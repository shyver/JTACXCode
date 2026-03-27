import SwiftUI
import SwiftData

@main
struct MilitaryRadioApp: App {
    let container: ModelContainer

    init() {
        do {
            let modelContainer = try ModelContainer(for: AssetCallsign.self, AirDefenseSystem.self, RedWeapon.self)
            self.container = modelContainer
            
            // Seed initial data if the database is empty
            Task { @MainActor [modelContainer] in
                seedData(context: modelContainer.mainContext)
            }
        } catch {
            fatalError("Failed to create ModelContainer for SwiftData")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}

@MainActor
private func seedData(context: ModelContext) {
    let airDefenseDescriptor = FetchDescriptor<AirDefenseSystem>()
    let existingAirDefense = (try? context.fetch(airDefenseDescriptor)) ?? []
    
    // Only seed if empty
    if existingAirDefense.isEmpty {
        let seeds: [(name: String, range: Double, alt: Int, guidance: String, type: AirDefenseType)] = [
            // MANPADS
            ("SA-14 Gremlin", 3.2, 19700, "IR", .manpads),
            ("SA-16 Gimlet", 2.7, 11500, "IR", .manpads),
            ("SA-18 Grouse", 2.8, 11500, "IR", .manpads),
            ("SA-24 Grinch", 4.3, 11500, "IR", .manpads),
            ("Verba", 4.0, 17000, "multispectral 9 (UV, NIR, MIR)", .manpads),
            ("QW1", 2.7, 13000, "IR", .manpads),
            ("Stinger Basic", 4.0, 9800, "IR", .manpads),
            ("SA-9 Gaskin", 2.3, 11500, "Optical photo contrast homing", .manpads),
            ("SA-13 Gopher", 2.7, 11500, "combined IR/ Optical photo contrast homing", .manpads),
            ("SA-19 Grison", 6.5, 26200, "Radar Acqu / Radio comand", .manpads),
            ("SA-8 Gecko", 5.5, 16500, "Radar Acqu / Radio comand", .manpads),
            ("SA-15 Gaunlet", 6.5, 19600, "Radar Acqu / Radio comand", .manpads),
            ("SA-22 Greyhood", 10.8, 49200, "Radar and EO Acqu / Radio comand", .manpads),

            // MRADS
            ("SA-1 Guild", 18.0, 82000, "Radar Acqu / Radio comand", .mrads),
            ("SA-2f", 18.4, 98000, "Radar Acqu / Radio comand", .mrads),
            ("SA-2d", 23.2, 98000, "Radar Acqu / Radio comand", .mrads),
            ("CSA-2", 32.4, 59100, "Radar Acqu / Radio comand", .mrads),
            ("SA-13 Goa", 13.0, 46000, "Radar and EO Acqu / Radio comand", .mrads),
            ("SA-26", 15.1, 65600, "Radar and EO Acqu / Radio comand", .mrads),
            ("SA-4 Ganef", 27.0, 82000, "Radar Acqu / Radio comand", .mrads),
            ("SA-6 Gainful", 13.4, 46000, "Radar Acqu / Radio comand", .mrads),
            ("SA-11 Gadfly", 17.0, 72000, "Radar Acqu / Radio comand", .mrads),
            ("SA-17 Grizzly", 17.0, 82000, "Radar Acqu / Radio comand / Terminal SARH,ARH", .mrads),
            ("ROLLAND 2", 4.3, 18000, "Mobile AAA , 20km/H", .mrads),
            ("Crotale / Shahine", 15.0, 180000, "Mobile AAA , 20km/H", .mrads),

            // LRADS
            ("S-200", 160.0, 100000, "RADAR Semi-active", .lrads),
            ("S-300", 110.0, 90000, "RADAR & active missile radar", .lrads),
            ("PATRIOT PAC2", 85.0, 80000, "RADAR Semi-active", .lrads),
            ("THAAD", 120.0, 150000, "", .lrads)
        ]
        
        for seed in seeds {
            let sys = AirDefenseSystem(
                name: seed.name,
                type: seed.type,
                maxEffectiveRangeNM: seed.range,
                maxAltitudeFt: seed.alt,
                guidance: seed.guidance
            )
            context.insert(sys)
        }
        try? context.save()
    }
    
    let assetDescriptor = FetchDescriptor<AssetCallsign>()
    let existingAssets = (try? context.fetch(assetDescriptor)) ?? []
    
    if existingAssets.isEmpty {
        let assetSeeds: [(aircraft: String, unit: Int, type: AssetType, callsigns: [String])] = [
            ("F-5 Tiger II", 15, .fixedWing, ["FALCON", "ZOOMER", "DIVER", "SHOOTER"]),
            ("C-130 H", 21, .fixedWing, ["HERCULE"]),
            ("C-130 J", 11, .fixedWing, ["TANIT"]),
            ("OH-58 KIOWA", 34, .rotaryWing, ["COBRA"]),
            ("OH-58 KIOWA", 37, .rotaryWing, ["VIPER"]),
            ("UH-60 BLACK HAWK", 36, .rotaryWing, ["PANTHER"]),
            ("Cessna 208", 41, .fixedWing, ["SKYBIRD"]),
            ("Cessna 208", 42, .fixedWing, ["SCOUT"]),
            ("AB-205", 32, .rotaryWing, ["TIGER"]),
            ("T-6 TEXAN", 13, .fixedWing, ["Lynx"]),
            ("AS-350", 31, .rotaryWing, ["FAHD"]),
            ("ANKA", 52, .uav, ["EAGLE"])
        ]
        
        for seed in assetSeeds {
            let asset = AssetCallsign(
                aircraft: seed.aircraft,
                airUnit: seed.unit,
                type: seed.type,
                callsigns: seed.callsigns
            )
            context.insert(asset)
        }
        try? context.save()
    }
    
    let redWeaponDescriptor = FetchDescriptor<RedWeapon>()
    let existingReds = (try? context.fetch(redWeaponDescriptor)) ?? []
    
    if existingReds.isEmpty {
        let redSeeds: [(weapon: String, type: RedWeaponType, lethal: Int, frag: Int, dangerClose: Int, minSafe: Int)] = [
            ("GBU-12", .bomb, 75, 500, 500, 425),
            ("GBU-31", .bomb, 120, 900, 900, 800),
            ("GBU-32", .bomb, 100, 700, 700, 600),
            ("GBU-38", .bomb, 75, 500, 500, 425),
            ("GBU-54", .bomb, 75, 500, 500, 425),
            ("Mk-82", .bomb, 75, 500, 500, 425),
            ("Mk-84", .bomb, 120, 900, 900, 800),
            ("CBU-87", .bomb, 200, 1200, 1200, 1000),
            ("AGM-65", .missile, 30, 200, 200, 150),
            ("20mm GUN", .gun, 10, 50, 100, 75),
            ("30mm GUN", .gun, 15, 75, 150, 100),
            ("2.75\" Hydra 70 HE (M151)", .rocket, 10, 50, 150, 100),
            ("Mk-81", .bomb, 50, 350, 350, 275),
            ("Mk-83", .bomb, 100, 700, 700, 600)
        ]
        
        for seed in redSeeds {
            let red = RedWeapon(
                weapon: seed.weapon,
                type: seed.type,
                lethalRadiusFt: seed.lethal,
                fragRadiusFt: seed.frag,
                dangerCloseFt: seed.dangerClose,
                minSafeTroopsOpenFt: seed.minSafe
            )
            context.insert(red)
        }
        try? context.save()
    }
}

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    @State private var currentScreen: AppScreen = .home

    // Keep local AppScreen in sync with MainViewModel navigation (tap-to-expand).
    private func syncScreenFromViewModel() {
        // Don’t override the onboarding flow screens.
        guard currentScreen != .home && currentScreen != .newMission else { return }

        switch viewModel.currentView {
        case .main:
            currentScreen = .main
        case .liveTranscript:
            currentScreen = .liveTranscript
        case .nineLine:
            currentScreen = .nineLine
        case .map:
            currentScreen = .map
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Main navigation container
            Group {
                switch currentScreen {
                case .home:
                    HomeView(currentView: $currentScreen)
                case .newMission:
                    NewMissionView(viewModel: viewModel, currentView: $currentScreen)
                case .main:
                    MainView(viewModel: viewModel)
                        .transition(.opacity)
                case .liveTranscript:
                    LiveTranscriptView(viewModel: viewModel)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .nineLine:
                    NineLineView(viewModel: viewModel, jtacViewModel: viewModel.jtacViewModel)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .map:
                    MapView(viewModel: viewModel)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .database:
                    DatabaseRootView(currentView: $currentScreen)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            // When ViewModel navigation changes, reflect it in the top-level screen.
            .onChange(of: viewModel.currentView) { _, _ in
                syncScreenFromViewModel()
            }
            // When StatusBar requests returning to Home, honor it here.
            .onChange(of: viewModel.shouldReturnToHome) { _, shouldReturn in
                guard shouldReturn else { return }
                currentScreen = .home
                viewModel.consumeReturnToHomeRequest()
            }
            // When StatusBar requests returning to New Mission, honor it here.
            .onChange(of: viewModel.shouldReturnToNewMission) { _, shouldReturn in
                guard shouldReturn else { return }
                currentScreen = .newMission
                viewModel.consumeReturnToNewMissionRequest()
            }
            // When switching to .main via the New Mission flow, ensure the VM matches.
            .onChange(of: currentScreen) { _, newValue in
                if newValue == .main {
                    viewModel.currentView = .main
                }
            }
        }
    }
}
