import Foundation

// MARK: - Main Mission Data Structure
struct MissionData {
    var campaignMissionName: String
    /// Mission authentication / challenge-response / codeword.
    var authentication: String
    var casCheckin: CASCheckin
    var aircraftType: String
    var frequencies: Frequencies
    var ordnanceLoadout: [String]
    var spinsNotes: SPINSNotes
}

// MARK: - Nested Data Structures
struct CASCheckin {
    var callsign: String
    var jtacCallsign: String
    var playTime: String
    var capabilities: String
    var laserCode: String
    var vdlCode: String
    var abortCode: String
}

struct Frequencies {
    var primary: String
    var guardFreq: String
    var jtac: String
}

struct SPINSNotes {
    var geometryPoints: [GeometryPoint]
    var friendlyForces: [FriendlyForce]
    var otherAssets: [OtherAsset]
}

// MARK: - SPINS Notes Details
struct GeometryPoint: Identifiable {
    let id = UUID()
    var type: PointType = .ip
    var name: String = ""
    var latitude: String = ""
    var longitude: String = ""
    var notes: String = ""
}

enum PointType: String, CaseIterable, Identifiable {
    case ip = "IP"
    case hold = "HOLD"
    case bp = "BP"
    case cp = "CP"
    case other = "Other"
    
    var id: Self { self }
}

struct FriendlyForce: Identifiable {
    let id = UUID()
    var type: FriendlyForceType = .flot
    var nameUnit: String = ""
    var latitude: String = ""
    var longitude: String = ""
    var notes: String = ""
}

enum FriendlyForceType: String, CaseIterable, Identifiable {
    case flot = "FLOT"
    case fscl = "FSCL"
    case cfl = "CFL"
    case rfl = "RFL"
    case unit = "UNIT"
    case other = "OTHER"
    
    var id: Self { self }
}

struct OtherAsset: Identifiable {
    let id = UUID()
    var asset: String = ""
    var type: String = ""
    var callsign: String = ""
    var freq: String = ""
    var latitude: String = ""
    var longitude: String = ""
    var notes: String = ""
}
