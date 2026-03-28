import Foundation

// MARK: - Main Mission Data Structure
struct MissionData: Codable {
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
struct CASCheckin: Codable {
    var callsign: String
    var jtacCallsign: String
    var playTime: String
    var capabilities: String
    var laserCode: String
    var vdlCode: String
    var abortCode: String
}

struct Frequencies: Codable {
    var primary: String
    var guardFreq: String
    var jtac: String
}

struct SPINSNotes: Codable {
    var geometryPoints: [GeometryPoint]
    var friendlyForces: [FriendlyForce]
    var otherAssets: [OtherAsset]
}

// MARK: - SPINS Notes Details
struct GeometryPoint: Identifiable, Codable {
    var id = UUID()
    var type: PointType = .ip
    var name: String = ""
    var latitude: String = ""
    var longitude: String = ""
    var notes: String = ""
}

enum PointType: String, CaseIterable, Identifiable, Codable {
    case ip = "IP"
    case hold = "HOLD"
    case bp = "BP"
    case cp = "CP"
    case other = "Other"
    
    var id: Self { self }
}

struct FriendlyForce: Identifiable, Codable {
    var id = UUID()
    var type: FriendlyForceType = .flot
    var nameUnit: String = ""
    var latitude: String = ""
    var longitude: String = ""
    var notes: String = ""
}

enum FriendlyForceType: String, CaseIterable, Identifiable, Codable {
    case flot = "FLOT"
    case fscl = "FSCL"
    case cfl = "CFL"
    case rfl = "RFL"
    case unit = "UNIT"
    case other = "OTHER"
    
    var id: Self { self }
}

struct OtherAsset: Identifiable, Codable {
    var id = UUID()
    var asset: String = ""
    var type: String = ""
    var callsign: String = ""
    var freq: String = ""
    var latitude: String = ""
    var longitude: String = ""
    var notes: String = ""
}
