import Foundation
import SwiftData

@Model
final class AssetCallsign {
    // Asset
    var aircraft: String
    var airUnit: Int
    var typeRaw: String

    // Callsigns (multiple)
    var callsigns: [String]

    // Metadata
    var createdAt: Date

    init(
        aircraft: String = "",
        airUnit: Int = 0,
        type: AssetType = .fixedWing,
        callsigns: [String] = [],
        createdAt: Date = Date()
    ) {
        self.aircraft = aircraft
        self.airUnit = airUnit
        self.typeRaw = type.rawValue
        self.callsigns = callsigns
        self.createdAt = createdAt
    }

    var type: AssetType {
        get { AssetType(rawValue: typeRaw) ?? .fixedWing }
        set { typeRaw = newValue.rawValue }
    }
}

enum AssetType: String, CaseIterable, Identifiable {
    case fixedWing = "Fixed Wing"
    case rotaryWing = "Rotary Wing"
    case uav = "UAV"

    var id: String { rawValue }
}

@Model
final class AirDefenseSystem {
    var name: String
    var maxEffectiveRangeNM: Double
    var maxAltitudeFt: Int
    var guidance: String
    var createdAt: Date

    init(
        name: String = "",
        maxEffectiveRangeNM: Double = 0,
        maxAltitudeFt: Int = 0,
        guidance: String = "",
        createdAt: Date = Date()
    ) {
        self.name = name
        self.maxEffectiveRangeNM = maxEffectiveRangeNM
        self.maxAltitudeFt = maxAltitudeFt
        self.guidance = guidance
        self.createdAt = createdAt
    }
}

@Model
final class RedWeapon {
    var weapon: String
    var lethalRadiusFt: Int
    var fragRadiusFt: Int
    var dangerCloseFt: Int
    var minSafeTroopsOpenFt: Int
    var createdAt: Date

    init(
        weapon: String = "",
        lethalRadiusFt: Int = 0,
        fragRadiusFt: Int = 0,
        dangerCloseFt: Int = 0,
        minSafeTroopsOpenFt: Int = 0,
        createdAt: Date = Date()
    ) {
        self.weapon = weapon
        self.lethalRadiusFt = lethalRadiusFt
        self.fragRadiusFt = fragRadiusFt
        self.dangerCloseFt = dangerCloseFt
        self.minSafeTroopsOpenFt = minSafeTroopsOpenFt
        self.createdAt = createdAt
    }
}
