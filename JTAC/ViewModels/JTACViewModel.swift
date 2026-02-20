import Foundation

class JTACViewModel: ObservableObject {

    /// Full accumulated transcript text across all completed segments this session.
    @Published var runningTranscript: String = ""

    /// Structured JTAC data extracted from the transcript. Updates after every segment.
    /// **Set directly** by `reparse()` / `process()` — NOT via Combine observation.
    /// This avoids the async hop that `.receive(on: DispatchQueue.main)` introduces,
    /// which previously caused the report to flash empty on every silence commit.
    @Published var report: JTACReport = JTACReport()

    private let parser = JTACParser()

    // MARK: - Public API

    /// Receives the **full accumulated transcript** from SpeechManager.
    /// Resets the parser and re-processes the complete text from scratch every
    /// time, eliminating any incremental-segment edge cases.
    ///
    /// The report is copied **synchronously** after processing so the UI
    /// never sees an intermediate empty state.
    func reparse(fullText: String) {
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        runningTranscript = trimmed
        parser.reset()
        parser.process(segment: trimmed)
        // Snapshot the fully-populated report in one atomic write.
        // No Combine hop → the UI goes directly from old-report to new-report
        // with zero intermediate empty state.
        report = parser.report
    }

    /// Legacy incremental API — still used by manual injection if needed.
    func process(segment: String) {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if runningTranscript.isEmpty {
            runningTranscript = trimmed
        } else {
            runningTranscript += "\n" + trimmed
        }

        parser.process(segment: trimmed)
        report = parser.report
    }

    /// Resets all state — call when starting a new mission/session.
    func reset() {
        runningTranscript = ""
        parser.reset()
        report = JTACReport()
    }

    // MARK: - Formatted content helpers for the UI

    /// Returns formatted display text for each sidebar category.
    func content(for category: String) -> String {
        switch category {
        case "CAS":
            guard let cas = report.cas else { return "" }
            // Always render all rows; fill "—" when a field hasn't been heard yet.
            func val(_ v: String?) -> String { v ?? "—" }
            var lines: [String] = []
            if let type_ = cas.type, let ctrl = cas.control {
                lines.append("CONTROL : \(type_) / \(ctrl)")
            }
            lines.append("CALLSIGN     : \(val(cas.callsign))")
            lines.append("MISSION      : \(val(cas.mission))")
            lines.append("AIRCRAFT TYPE: \(val(cas.aircraftType))")
            lines.append("POS AND ALT  : \(val(cas.posAndAlt))")
            lines.append("ORDNANCE     : \(val(cas.ordnance))")
            lines.append("PLAY TIME    : \(val(cas.playtime))")
            lines.append("CAPES        : \(val(cas.capes))")
            lines.append("LASER CODE   : \(val(cas.laserCode))")
            lines.append("VDL CODE     : \(val(cas.vdlCode))")
            lines.append("ABORT CODE   : \(val(cas.abortCode))")
            return lines.joined(separator: "\n")

        case "SOF":
            guard let s = report.safetyOfFlight, !s.isEmpty else { return "" }
            func sofVal(_ v: String?) -> String { v ?? "/" }
            return [
                "1-THREATS                : \(sofVal(s.threats))",
                "2-FRIENDLY ASSETS        : \(sofVal(s.friendlyAssets))",
                "3-TERRAINS AND OBSTACLES : \(sofVal(s.terrainsObstacles))",
                "4-EMERGENCY CONSIDERATIONS: \(sofVal(s.emergencyConsiderations))",
            ].joined(separator: "\n")

        case "S. UPDATE":
            guard let s = report.situationUpdate, !s.isEmpty else { return "" }
            func val(_ v: String?) -> String { v ?? "//" }
            var lines: [String] = []
            lines.append("THREATS             : \(val(s.threats))")
            lines.append("TARGETS/ENEMY       : \(val(s.targets))")
            lines.append("FRIENDLIES          : \(val(s.friendlies))")
            lines.append("ARTY                : \(val(s.arty))")
            lines.append("CLEARANCE           : \(val(s.clearance))")
            lines.append("ORDNANCE            : \(val(s.ordnance))")
            lines.append("REMARKS/RESTRICTIONS: \(val(s.remarks))")
            return lines.joined(separator: "\n")

        case "9 Line":
            guard let nl = report.nineLine else { return "" }
            var lines: [String] = []
            if let v = nl.ip                { lines.append("Line 1  IP              : \(v)") }
            if let v = nl.heading           { lines.append("Line 2  Heading         : \(v)") }
            if let v = nl.distance          { lines.append("Line 3  Distance        : \(v)") }
            if let v = nl.targetElevation   { lines.append("Line 4  Elevation       : \(v)") }
            if let v = nl.targetDescription { lines.append("Line 5  Target Desc     : \(v)") }
            if let v = nl.targetMark        { lines.append("Line 6  Location (MGRS) : \(v)") }
            if let v = nl.friendlies        { lines.append("Line 7  Mark Type       : \(v)") }
            if let v = nl.egress            { lines.append("Line 8  Friendlies      : \(v)") }
            if let v = nl.remarksLine       { lines.append("Line 9  Egress/Remarks  : \(v)") }
            return lines.joined(separator: "\n")

        case "Remarks":
            return report.remarks ?? ""

        case "Restrictions":
            return report.restrictions ?? ""

        case "BDA":
            return report.bda ?? ""

        case "GamePlan":
            return report.gamePlan ?? ""

        default:
            return ""
        }
    }

    /// True if the given category has any parsed data.
    func hasData(for category: String) -> Bool {
        !content(for: category).isEmpty
    }
}
