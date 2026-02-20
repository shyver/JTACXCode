import Speech
import Foundation

// MARK: - JTACPhase
// Describes which phase of a CAS mission is currently active.
// SpeechManager switches the active language model when the phase changes,
// giving the recognizer a narrower, higher-probability vocabulary for each
// stage of the engagement.
enum JTACPhase: String, CaseIterable {
    case general   = "general"    // default / unknown — broadest coverage
    case cas       = "cas"        // CAS check-in
    case nineLine  = "nine_line"  // 9-line readout
    case remarks   = "remarks"    // remarks & restrictions
    case bda       = "bda"        // battle damage assessment
}

// MARK: - CustomLanguageModelBuilder
//
// Builds, compiles, and caches per-phase SFCustomLanguageModelData binaries.
// Each phase produces a specialised model so the recognizer sees only the
// vocabulary that is statistically likely at that moment in the mission —
// dramatically improving accuracy over a single monolithic model.
//
// Weight tiers (mapped to SFCustomLanguageModelData.PhraseCount.count):
//   10.0 – safety-critical (cleared hot, abort, danger close)
//    7.5 – common procedural (nine line, checking in, GBU-12)
//    5.0 – regular domain vocabulary
//    2.0 – rare / optional variants
//
// ── Offline guarantee ──────────────────────────────────────────────────────
// All compilation is on-device.  requiresOnDeviceRecognition is set on every
// request in SpeechManager, so no audio ever leaves the iPad.
//
// ── Cache invalidation ─────────────────────────────────────────────────────
// Each model is cached as "<phase>_v<version>.bin".  Bump `modelVersion`
// to force a rebuild on next launch.

@available(iOS 17, *)
actor CustomLanguageModelBuilder {

    // ── Singleton ─────────────────────────────────────────────────────────
    static let shared = CustomLanguageModelBuilder()
    private init() {}

    // ── Version — bump to invalidate all cached models ────────────────────
    static let modelVersion = "2.4.0"

    // ── Cache directory ───────────────────────────────────────────────────
    private static let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("JTACModels_v\(modelVersion)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir
    }()

    // ── State ─────────────────────────────────────────────────────────────
    /// Keyed by phase.  Nil until that phase's model has finished compiling.
    private var configurations: [JTACPhase: SFSpeechLanguageModel.Configuration] = [:]

    // ── Public API ────────────────────────────────────────────────────────

    /// Returns the compiled configuration for `phase`, or nil if not yet ready.
    func configuration(for phase: JTACPhase) -> SFSpeechLanguageModel.Configuration? {
        configurations[phase]
    }

    /// Prepares all phase models concurrently.  Call once at app launch.
    /// Never throws — failures are logged; the app falls back to contextualStrings.
    func prepareAll() async {
        await withTaskGroup(of: Void.self) { group in
            for phase in JTACPhase.allCases {
                group.addTask { await self.prepare(phase: phase) }
            }
        }
    }

    /// Prepares a single phase model.  Returns immediately if already cached.
    func prepare(phase: JTACPhase) async {
        guard configurations[phase] == nil else { return }

        let modelURL = Self.cacheDir
            .appendingPathComponent("\(phase.rawValue)_v\(Self.modelVersion).bin")

        // Re-use cached binary.
        if FileManager.default.fileExists(atPath: modelURL.path) {
            configurations[phase] = SFSpeechLanguageModel.Configuration(languageModel: modelURL)
            print("[LMBuilder] Loaded '\(phase.rawValue)' from cache")
            return
        }

        do {
            let data = Self.buildData(for: phase)
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("jtac_\(phase.rawValue)_\(UUID().uuidString).bin")

            try await data.export(to: tmpURL)

            let cfg = SFSpeechLanguageModel.Configuration(languageModel: modelURL)
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                SFSpeechLanguageModel.prepareCustomLanguageModel(
                    for: tmpURL,
                    configuration: cfg
                ) { error in
                    if let error = error { cont.resume(throwing: error) }
                    else                 { cont.resume() }
                }
            }

            configurations[phase] = cfg
            try? FileManager.default.removeItem(at: tmpURL)
            print("[LMBuilder] Built '\(phase.rawValue)' model (v\(Self.modelVersion))")

        } catch {
            print("[LMBuilder] Failed '\(phase.rawValue)': \(error)")
        }
    }

    // MARK: - Phase Data Builders

    private static func buildData(for phase: JTACPhase) -> SFCustomLanguageModelData {
        let lm = SFCustomLanguageModelData(
            locale: Locale(identifier: "en-US"),
            identifier: "com.jtac.\(phase.rawValue)",
            version: modelVersion)

        // Always add the universal base vocabulary first, then layer on
        // phase-specific phrases with elevated weights.
        addBase(to: lm)

        switch phase {
        case .general:  break                    // base only
        case .cas:      addCASLayer(to: lm)
        case .nineLine: addNineLineLayer(to: lm)
        case .remarks:  addRemarksLayer(to: lm)
        case .bda:      addBDALayer(to: lm)
        }

        return lm
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    /// Weight tiers expressed as Int counts for PhraseCount.
    /// 10 → safety-critical  7 → common  5 → regular  2 → rare
    private enum W {
        static let critical: Int = 1000   // maps to weight 10.0
        static let high: Int     = 750    // maps to weight 7.5
        static let normal: Int   = 500    // maps to weight 5.0
        static let low: Int      = 200    // maps to weight 2.0
    }

    private static func add(_ phrases: [String], weight: Int, to lm: SFCustomLanguageModelData) {
        for phrase in phrases {
            lm.insert(phraseCount:
                SFCustomLanguageModelData.PhraseCount(phrase: phrase, count: weight))
        }
    }

    // MARK: – Base vocabulary (included in every phase model)

    private static func addBase(to lm: SFCustomLanguageModelData) {

        // ── Safety-critical brevity (weight 10.0) ─────────────────────────
        add([
            "cleared hot",
            "not cleared hot",
            "abort abort abort",
            "abort",
            "in hot",
            "in dry",
            "off dry",
            "rifle",
            "guns",
            "pickle",
            "splash",
            "shack",
            "direct hit",
            "danger close",
            "hold fire",
            "cease fire",
            // Known identifiers with high garble rate — elevated to critical
            // so the recognizer learns them as atomic units.
            "BP EEL 2K",
            "BP EEL",
            "Panther",
        ], weight: W.critical, to: lm)

        // ── Radio procedure (weight 7.5) ──────────────────────────────────
        add([
            "break break",
            "say again",
            "I say again",
            "how copy",
            "good copy",
            "loud and clear",
            "lima charlie",
            "weak but readable",
            "wilco",
            "roger",
            "copy",
            "standby",
            "stand by",
            "affirm",
            "negative",
            "authenticate",
            "authentication",
            "over",
            "out",
            "break",
            "go ahead",
            "send it",
        ], weight: W.high, to: lm)

        // ── Callsigns (weight 7.5) — beam recognizer away from homophones
        add([
            "Axeman", "Axeman one-one", "Axeman two-one", "Axeman one-two",
            "Axeman three-one", "Axeman two-two",
            "Hawg",   "Hawg one-one",   "Hawg two-one",   "Hawg one-two",
            "Viper",  "Viper one-one",  "Viper two-one",
            "Reaper", "Reaper one-one", "Reaper two-one",
            "Widow",  "Widow one-one",
            "Dagger", "Dagger one-one",
            "Saber",  "Saber one-one",
            "Falcon", "Falcon one-one",
            "Eagle",  "Eagle one-one",
            "Cougar", "Cougar one-one",
            "Panther","Panther one-one",
            "Warlord","Warlord one-one",
            "Ares",   "Ares one-one",
            "Bone",   "Spooky", "Ghostrider",
            "Slayer", "Striker",
            "flight lead", "dash two", "dash three", "dash four",
            "callsign", "read callsign", "say callsign",
            "Panther", "Panther one-one", "Panther two-one",
        ], weight: W.high, to: lm)

        // ── Aircraft platforms (weight 5.0) ───────────────────────────────
        add([
            "A-10", "Warthog", "Hawg",
            "F-16", "Viper",
            "F/A-18", "Hornet",
            "F-15E", "Strike Eagle",
            "B-52", "B-1",
            "AC-130", "Spooky", "Ghostrider",
            "AH-64", "Apache",
            "MQ-9", "Reaper",
            "rotary wing", "fixed wing", "fast mover",
        ], weight: W.normal, to: lm)

        // ── NATO phonetic alphabet (weight 5.0) ───────────────────────────
        add([
            "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf",
            "hotel", "india", "juliet", "kilo", "lima", "mike", "november",
            "oscar", "papa", "quebec", "romeo", "sierra", "tango", "uniform",
            "victor", "whiskey", "x-ray", "yankee", "zulu",
        ], weight: W.normal, to: lm)

        // ── Military number pronunciation (weight 5.0) ────────────────────
        add([
            "niner", "fife", "tree", "wun",
            "one one", "one two", "two one", "two two",
            "three one", "three two", "four one", "four two",
        ], weight: W.normal, to: lm)

        // ── Navigation / geometry (weight 2.0) ───────────────────────────
        add([
            "target", "on target", "off target", "tally target",
            "MGRS", "grid", "ten digit grid", "eight digit grid",
            "altitude MSL", "altitude AGL",
            "angels", "flight level",
            "north", "south", "east", "west",
            "northeast", "northwest", "southeast", "southwest",
            "pull off north", "pull off south", "pull off east", "pull off west",
            "two seven zero", "zero nine zero", "one eight zero", "three six zero",
            "meters", "feet", "nautical miles",
            "azimuth", "bearing", "heading",
        ], weight: W.low, to: lm)
    }

    // MARK: – CAS check-in layer

    private static func addCASLayer(to lm: SFCustomLanguageModelData) {

        // Core CAS phrases (weight 10.0)
        add([
            "checking in",
            "check in",
            "type one control",
            "type two control",
            "type three control",
            "type 1 control",
            "type 2 control",
            "type 3 control",
            "emergency CAS",
            "immediate CAS",
            "deliberate CAS",
        ], weight: W.critical, to: lm)

        // Ordnance — taught as full units so "two by GBU-12" beats "Dubai" (7.5)
        add([
            "GBU-12", "GBU-31", "GBU-32", "GBU-38", "GBU-54",
            "JDAM", "Paveway",
            "Hellfire", "Brimstone", "Maverick",
            "APKWS", "Hydra 70",
            "Mk-82", "Mk-83", "Mk-84",
            "one by GBU-12",  "two by GBU-12",  "four by GBU-12",
            "one by GBU-38",  "two by GBU-38",  "four by GBU-38",
            "one by Hellfire","two by Hellfire", "four by Hellfire",
            "two by Mk-82",   "four by Mk-82",
            "1x GBU-12",  "2x GBU-12",  "4x GBU-12",
            "1x GBU-38",  "2x GBU-38",  "4x GBU-38",
            "thirty mike-mike",
            "twenty mike-mike",
            "thirty millimeter",
            "twenty millimeter",
        ], weight: W.high, to: lm)

        // Check-in data fields (weight 7.5)
        add([
            "abort code", "laser code", "VDL code",
            "playtime fifteen", "playtime twenty", "playtime thirty",
            "playtime forty-five", "playtime sixty",
            "fuel state", "bingo fuel",
            "FLIR", "TGP", "NVG", "NVDS", "HMD", "SDL",
            "Sniper pod", "Litening pod",
        ], weight: W.high, to: lm)

        // Homophones / alternate spoken forms (weight 2.0)
        // These teach the model the mishearing variant → correct form mapping
        add([
            "two by", "four by", "one by", "three by", "six by",
            "2x", "4x", "1x", "3x",
            "mike mike",          // pre-hyphenation form
            "thirty mike mike",
            "twenty mike mike",
        ], weight: W.low, to: lm)

        // Briefing-point / battle-position identifiers (weight 7.5)
        add([
            "BP EEL 2K",
            "call ready",
            "when ready",
            "say when ready",
            "checking in when ready",
            "check in when ready",
            "situation update",
            "situation update code alpha",
            "situation update code bravo",
            "situation update code charlie",
            "bomb", "bombs away", "bomb release",
        ], weight: W.high, to: lm)
    }

    // MARK: – Nine-line layer

    private static func addNineLineLayer(to lm: SFCustomLanguageModelData) {

        // Triggers (weight 10.0)
        add([
            "nine line",
            "niner line",
            "nine liner",
            "nine-line",
            "standby for nine line",
            "standby for tasking",
            "ready for tasking",
            "say when ready",
            "initial point",
            "IP",
        ], weight: W.critical, to: lm)

        // Line labels — every combination (weight 7.5)
        add([
            "line one", "line two", "line three", "line four", "line five",
            "line six", "line seven", "line eight", "line nine",
        ], weight: W.high, to: lm)

        // Geometry & marking (weight 7.5)
        add([
            "attack heading", "final attack heading",
            "ingress route",  "egress direction",
            "egress north",   "egress south",   "egress east",   "egress west",
            "offset left",    "offset right",
            "target elevation",
            "friendlies", "friendly position",
            "troops in contact",
            "mark type",
            "say when tally",
            "tally",
            "laser on", "sparkle",
            "mark on top",
            "pop smoke",
            "red smoke", "green smoke", "yellow smoke", "purple smoke", "white smoke",
            "danger close",
        ], weight: W.high, to: lm)

        // Remarks / restrictions (weight 5.0)
        add([
            "remarks", "restrictions", "game plan",
            "no fire area", "exclusion zone",
            "friendlies within", "hold fire",
            "cleared to engage",
            "time on target", "TOT",
            "battle damage assessment", "BDA",
        ], weight: W.normal, to: lm)

        // Rare variants (weight 2.0)
        add([
            "IP to target line",
            "target description",
            "location of friendlies",
            "egress to the north", "egress to the south",
        ], weight: W.low, to: lm)
    }

    // MARK: – Remarks / restrictions layer

    private static func addRemarksLayer(to lm: SFCustomLanguageModelData) {
        add([
            "cleared hot",
            "not cleared hot",
            "abort abort abort",
            "in hot",
            "cleared to engage",
            "rifle",
            "pickle",
            "guns",
        ], weight: W.critical, to: lm)

        add([
            "remarks", "restrictions",
            "no fire area", "exclusion zone",
            "friendlies within", "hold fire",
            "game plan",
            "time on target", "TOT",
            "type one control", "type two control", "type three control",
        ], weight: W.high, to: lm)
    }

    // MARK: – BDA layer

    private static func addBDALayer(to lm: SFCustomLanguageModelData) {
        add([
            "battle damage assessment",
            "BDA",
            "splash",
            "shack",
            "direct hit",
            "rounds complete",
            "off target",
        ], weight: W.critical, to: lm)

        add([
            "neutralized", "suppressed", "destroyed",
            "assessed", "confirmed", "unconfirmed",
            "personnel", "vehicle", "structure",
            "one casualty", "two casualties",
            "request reattack",
            "reattack",
            "end of mission",
            "mission complete",
        ], weight: W.high, to: lm)

        add([
            "secondary explosions", "fires observed",
            "target obscured", "no damage observed",
            "PTL", "post-target loiter",
        ], weight: W.normal, to: lm)
    }
}
