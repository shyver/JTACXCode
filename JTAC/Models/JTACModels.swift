import Foundation

// MARK: - Top-level report

struct JTACReport {
    var cas: CASData?
    var situationUpdate: String?
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

// MARK: - CAS check-in

struct CASData {
    /// e.g. "Type 1", "Type 2", "Type 3"
    var type: String?
    /// e.g. "Type 1 Control"
    var control: String?
    /// Raw check-in text (weapons, playtime, fuel, etc.)
    var checkIn: String?
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
