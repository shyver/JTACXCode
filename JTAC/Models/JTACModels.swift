import Foundation

// MARK: - Top-level report

struct JTACReport {
    var cas: CASData?
    var situationUpdate: SituationUpdate?
    var nineLine: NineLine?
    var remarks: String?
    var restrictions: String?
    var bda: String?
    var gamePlan: String?

    var isEmpty: Bool {
        cas == nil &&
        situationUpdate == nil &&
        nineLine == nil &&
        remarks == nil &&
        restrictions == nil &&
        bda == nil &&
        gamePlan == nil
    }
}

// MARK: - Situation Update (SITREP)

struct SituationUpdate {
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

struct CASData {
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

struct NineLine {
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
