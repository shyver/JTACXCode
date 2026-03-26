import Foundation

/// Canonical definition of NineLine tabs so the collapsed (MainView) and expanded (NineLineView)
/// UIs stay in sync (order, labels, and selection).
struct NineLineTab: Identifiable, Hashable {
    /// Stable internal id used for selection persistence.
    let id: String
    /// Full label (expanded view).
    let title: String
    /// Short label (collapsed view sidebar).
    let shortTitle: String

    /// Key used to query `JTACViewModel` (transcript-parsed content).
    /// Tabs that are driven by mission data (e.g. CAS Check-In) can still set this
    /// to a best-effort key for the green-dot indicator.
    let jtacCategoryKey: String
}

enum NineLineTabs {
    /// Ordered list of tabs, as requested.
    static let all: [NineLineTab] = [
        .init(id: "authentication", title: "AUTHENTICATION", shortTitle: "AUTH", jtacCategoryKey: "AUTH"),
        .init(id: "safetyOfFlight", title: "Safety of FLIGHT", shortTitle: "SAFETY", jtacCategoryKey: "Safety"),
        .init(id: "casCheckIn", title: "CAS CHECK IN", shortTitle: "CAS", jtacCategoryKey: "CAS"),
        .init(id: "situationUpdate", title: "SITUATION UPDATE", shortTitle: "SIT", jtacCategoryKey: "S. UPDATE"),
        .init(id: "gamePlan", title: "GAME PLAN", shortTitle: "PLAN", jtacCategoryKey: "GamePlan"),
        .init(id: "nineLineBrief", title: "9 LINE BRIEF", shortTitle: "9-LINE", jtacCategoryKey: "9 Line"),
        .init(id: "remarks", title: "REMARKS", shortTitle: "RMKS", jtacCategoryKey: "Remarks"),
        .init(id: "restrictions", title: "RESTRICTIONS", shortTitle: "RSTR", jtacCategoryKey: "Restrictions"),
        .init(id: "bda", title: "BDA", shortTitle: "BDA", jtacCategoryKey: "BDA")
    ]

    static func tab(for id: String) -> NineLineTab? {
        all.first { $0.id == id }
    }

    static let `default` = "nineLineBrief"
}
