import Foundation
import SwiftData

@Model
class ArchivedMission {
    var id: UUID
    var date: Date
    var name: String
    
    // Storing complex Codable structures as JSON data
    var missionDataJSON: Data
    var reportJSON: Data
    
    init(id: UUID = UUID(), date: Date = Date(), name: String, missionData: MissionData, report: JTACReport) {
        self.id = id
        self.date = date
        self.name = name
        self.missionDataJSON = (try? JSONEncoder().encode(missionData)) ?? Data()
        self.reportJSON = (try? JSONEncoder().encode(report)) ?? Data()
    }
    
    var missionData: MissionData? {
        try? JSONDecoder().decode(MissionData.self, from: missionDataJSON)
    }
    
    var report: JTACReport? {
        try? JSONDecoder().decode(JTACReport.self, from: reportJSON)
    }
}
