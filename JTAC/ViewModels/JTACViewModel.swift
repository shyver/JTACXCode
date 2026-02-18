import Foundation
import Combine

class JTACViewModel: ObservableObject {

    /// Full accumulated transcript text across all completed segments this session.
    @Published var runningTranscript: String = ""

    /// Structured JTAC data extracted from the transcript. Updates after every segment.
    @Published var report: JTACReport = JTACReport()

    private let parser = JTACParser()
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Keep our published report in sync with the parser's published report.
        parser.$report
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newReport in
                self?.report = newReport
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Call with each completed transcript segment.
    /// Appends to runningTranscript and runs the parser.
    func process(segment: String) {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if runningTranscript.isEmpty {
            runningTranscript = trimmed
        } else {
            runningTranscript += "\n" + trimmed
        }

        parser.process(segment: trimmed)
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
            var lines: [String] = []
            if let type_ = cas.type       { lines.append("Type: \(type_)") }
            if let ctrl  = cas.control    { lines.append("Control: \(ctrl)") }
            if let ci    = cas.checkIn    { lines.append("\n\(ci)") }
            return lines.joined(separator: "\n")

        case "S. UPDATE":
            return report.situationUpdate ?? ""

        case "9 Line":
            guard let nl = report.nineLine else { return "" }
            var lines: [String] = []
            if let v = nl.ip                { lines.append("Line 1 (IP): \(v)") }
            if let v = nl.heading           { lines.append("Line 2 (Heading): \(v)") }
            if let v = nl.distance          { lines.append("Line 3 (Distance): \(v)") }
            if let v = nl.targetElevation   { lines.append("Line 4 (Elevation): \(v)") }
            if let v = nl.targetDescription { lines.append("Line 5 (Target): \(v)") }
            if let v = nl.targetMark        { lines.append("Line 6 (Mark): \(v)") }
            if let v = nl.friendlies        { lines.append("Line 7 (Friendlies): \(v)") }
            if let v = nl.egress            { lines.append("Line 8 (Egress): \(v)") }
            if let v = nl.remarksLine       { lines.append("Line 9 (Remarks): \(v)") }
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
