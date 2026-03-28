import Foundation

// MARK: - Top-level report

struct JTACReport: Codable {
    var cas: CASData?
    var situationUpdate: SituationUpdate?
    var safetyOfFlight: SafetyOfFlight?
    var nineLine: NineLine?
    var remarks: Remarks?
    var restrictions: Restrictions?
    var bda: BDAData?
    var gamePlan: GamePlan?

    var isEmpty: Bool {
        cas == nil &&
        situationUpdate == nil &&
        safetyOfFlight == nil &&
        nineLine == nil &&
        remarks == nil &&
        restrictions == nil &&
        bda == nil &&
        gamePlan == nil
    }
}

// MARK: - Remarks

struct Remarks: Codable {
    var laserTgtLine: String?
    var ptl: String?
    var gunTgtLine: String?
    var maxOrd: String?
    var text: String? // Fallback or extra text

    var isEmpty: Bool {
        laserTgtLine == nil && ptl == nil && gunTgtLine == nil && maxOrd == nil && text == nil
    }
}

// MARK: - Restrictions

struct Restrictions: Codable {
    var dangerClose: String?
    var fah: String?
    var acas: String?
    var totTtt: String?
    var latAlt: String?
    var postLaunchAbort: String?
    var text: String? // Fallback

    var isEmpty: Bool {
        dangerClose == nil && fah == nil && acas == nil && totTtt == nil &&
        latAlt == nil && postLaunchAbort == nil && text == nil
    }
}

// MARK: - BDA

struct BDAData: Codable {
    var status: String?   // SUCCESSFUL/UNSUCCESSFUL/UNKNOWN
    var size: String?
    var activity: String?
    var location: String?
    var time: String?
    var remarks: String?
    var text: String?     // Fallback text

    var isEmpty: Bool {
        status == nil && size == nil && activity == nil && location == nil &&
        time == nil && remarks == nil && text == nil
    }
}

// MARK: - Game Plan

struct GamePlan: Codable {
    var typeOfControl:  String?
    var methodOfAttack: String?
    var gcIntent:       String?
    var cde:            String?
    var ordnance:       String?
    var desiredEffect:  String?

    var isEmpty: Bool {
        typeOfControl == nil && methodOfAttack == nil && gcIntent == nil &&
        cde == nil && ordnance == nil && desiredEffect == nil
    }
}

// MARK: - Safety of Flight

struct SafetyOfFlight: Codable {
    var threats:              String?   // 1 — threats to the aircraft
    var friendlyAssets:       String?   // 2 — friendly aircraft/assets in the area
    var terrainsObstacles:    String?   // 3 — terrain, wires, towers, obstacles
    var emergencyConsiderations: String? // 4 — divert fields, FARP, SAR, bingo
    var ePoint:               String?   // 5 - E point

    var isEmpty: Bool {
        threats == nil && friendlyAssets == nil &&
        terrainsObstacles == nil && emergencyConsiderations == nil &&
        ePoint == nil
    }
}

// MARK: - Situation Update (SITREP)

struct SituationUpdate: Codable {
    var threats:     String?   // e.g. "Small arms and possible MANPADS"
    var targets:     String?   // enemy vehicles / forces description
    var friendlies:  String?   // friendly positions (unit, direction, distance)
    var arty:        String?   // artillery status (e.g. "1 COLD South 13km")
    var clearance:   String?   // clearance authority callsign (e.g. "ODIN11")
    var ordnance:    String?   // available ordnance (if stated)
    var remarks:     String?   // free remarks / restrictions

    var isEmpty: Bool {
        threats == nil && targets == nil && friendlies == nil &&
        arty == nil && clearance == nil && ordnance == nil && remarks == nil
    }
}

// MARK: - CAS check-in

struct CASData: Codable {
    var callsign:     String?   // e.g. "Viper 1-1"
    var mission:      String?   // mission number / type
    var aircraftType: String?   // e.g. "A-10C", "F-16C"
    var posAndAlt:    String?   // position and altitude
    var ordnance:     String?   // weapons load
    var playtime:     String?   // time on station
    var capes:        String?   // capabilities (e.g. FLIR, laser, NVG)
    var laserCode:    String?   // 4-digit laser code
    var vdlCode:      String?   // VDL / data-link code
    var abortCode:    String?   // abort code word
    // Control type extracted separately
    var type:    String?        // "Type 1" / "Type 2" / "Type 3"
    var control: String?        // "Type 1 Control" etc.
}

// MARK: - 9-Line brief

struct NineLine: Codable {
    var ip: String?               // Line 1 – Initial Point
    var heading: String?          // Line 2 – Heading from IP
    var distance: String?         // Line 3 – Distance from IP
    var targetElevation: String?  // Line 4 – Target elevation
    var targetDescription: String? // Line 5 – Description & location
    var targetMark: String?       // Line 6 – Mark type
    var friendlies: String?       // Line 7 – Friendlies location
    var egress: String?           // Line 8 – Egress
    var remarksLine: String?      // Line 9 – Remarks / restrictions
}

enum JTACPhase: String, CaseIterable {
    case general   = "general"    // default / unknown — broadest coverage
    case cas       = "cas"        // CAS check-in
    case nineLine  = "nine_line"  // 9-line readout
    case remarks   = "remarks"    // remarks & restrictions
    case bda       = "bda"        // battle damage assessment
}
