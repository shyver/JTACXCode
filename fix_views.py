import re

with open("/Users/pc/Documents/JTACXCode/JTAC/Views/NineLineView.swift", "r") as f:
    text = f.read()

def replacer(match):
    name = match.group(1)
    if name == "NineLineBriefDetailView":
        return """struct NineLineBriefDetailView: View {
    @ObservedObject var jtacViewModel: JTACViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<NineLine, String?>) -> Binding<String> {
        Binding(
            get: { jtacViewModel.report.nineLine?[keyPath: keyPath] ?? "" },
            set: { 
                if jtacViewModel.report.nineLine == nil { jtacViewModel.report.nineLine = NineLine() }
                jtacViewModel.report.nineLine?[keyPath: keyPath] = $0.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: "1. IP / BP", text: binding(for: \\.ip), isCompact: isCompact)
            EditableDetailRow(label: "2. HDG", text: binding(for: \\.heading), isCompact: isCompact)
            EditableDetailRow(label: "3. DISTANCE", text: binding(for: \\.distance), isCompact: isCompact)
            EditableDetailRow(label: "4. ELEVATION", text: binding(for: \\.targetElevation), isCompact: isCompact)
            EditableDetailRow(label: "5. TARGET", text: binding(for: \\.targetDescription), isCompact: isCompact)
            EditableDetailRow(label: "6. LOCATION", text: binding(for: \\.targetMark), isCompact: isCompact)
            EditableDetailRow(label: "7. MARK", text: binding(for: \\.friendlies), isCompact: isCompact)
            EditableDetailRow(label: "8. FRIENDLIES", text: binding(for: \\.egress), isCompact: isCompact)
            EditableDetailRow(label: "9. EGRESS", text: binding(for: \\.remarksLine), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}
"""
    elif name == "SafetyOfFlightDetailView":
        return """struct SafetyOfFlightDetailView: View {
    @ObservedObject var jtacViewModel: JTACViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<SafetyOfFlight, String?>) -> Binding<String> {
        Binding(
            get: { jtacViewModel.report.safetyOfFlight?[keyPath: keyPath] ?? "" },
            set: { 
                if jtacViewModel.report.safetyOfFlight == nil { jtacViewModel.report.safetyOfFlight = SafetyOfFlight() }
                jtacViewModel.report.safetyOfFlight?[keyPath: keyPath] = $0.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: "1. THREATS", text: binding(for: \\.threats), isCompact: isCompact)
            EditableDetailRow(label: "2. FRIENDLY ASSETS", text: binding(for: \\.friendlyAssets), isCompact: isCompact)
            EditableDetailRow(label: "3. TERRAINS AND OBSTACLES", text: binding(for: \\.terrainsObstacles), isCompact: isCompact)
            EditableDetailRow(label: "4. EMERGENCY CONSIDERATIONS", text: binding(for: \\.emergencyConsiderations), isCompact: isCompact)
            EditableDetailRow(label: "5. E POINT", text: binding(for: \\.ePoint), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}
"""
    elif name == "SituationUpdateDetailView":
        return """struct SituationUpdateDetailView: View {
    @ObservedObject var jtacViewModel: JTACViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<SituationUpdate, String?>) -> Binding<String> {
        Binding(
            get: { jtacViewModel.report.situationUpdate?[keyPath: keyPath] ?? "" },
            set: { 
                if jtacViewModel.report.situationUpdate == nil { jtacViewModel.report.situationUpdate = SituationUpdate() }
                jtacViewModel.report.situationUpdate?[keyPath: keyPath] = $0.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: "THREATS", text: binding(for: \\.threats), isCompact: isCompact)
            EditableDetailRow(label: "TARGETS/ENEMY", text: binding(for: \\.targets), isCompact: isCompact)
            EditableDetailRow(label: "FRIENDLIES", text: binding(for: \\.friendlies), isCompact: isCompact)
            EditableDetailRow(label: "ARTY", text: binding(for: \\.arty), isCompact: isCompact)
            EditableDetailRow(label: "CLEARANCE", text: binding(for: \\.clearance), isCompact: isCompact)
            EditableDetailRow(label: "ORDNANCE", text: binding(for: \\.ordnance), isCompact: isCompact)
            EditableDetailRow(label: "REMARKS/RESTRICTIONS", text: binding(for: \\.remarks), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}
"""
    elif name == "GamePlanDetailView":
        return """struct GamePlanDetailView: View {
    @ObservedObject var jtacViewModel: JTACViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<GamePlan, String?>) -> Binding<String> {
        Binding(
            get: { jtacViewModel.report.gamePlan?[keyPath: keyPath] ?? "" },
            set: { 
                if jtacViewModel.report.gamePlan == nil { jtacViewModel.report.gamePlan = GamePlan() }
                jtacViewModel.report.gamePlan?[keyPath: keyPath] = $0.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: "TYPE OF CONTROL", text: binding(for: \\.typeOfControl), isCompact: isCompact)
            EditableDetailRow(label: "METHOD OF ATTACK", text: binding(for: \\.methodOfAttack), isCompact: isCompact)
            EditableDetailRow(label: "GC INTENT", text: binding(for: \\.gcIntent), isCompact: isCompact)
            EditableDetailRow(label: "CDE", text: binding(for: \\.cde), isCompact: isCompact)
            EditableDetailRow(label: "ORDNANCE", text: binding(for: \\.ordnance), isCompact: isCompact)
            EditableDetailRow(label: "DESIRED EFFECT", text: binding(for: \\.desiredEffect), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}
"""
    elif name == "RemarksDetailView":
        return """struct RemarksDetailView: View {
    @ObservedObject var jtacViewModel: JTACViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<Remarks, String?>) -> Binding<String> {
        Binding(
            get: { jtacViewModel.report.remarks?[keyPath: keyPath] ?? "" },
            set: { 
                if jtacViewModel.report.remarks == nil { jtacViewModel.report.remarks = Remarks() }
                jtacViewModel.report.remarks?[keyPath: keyPath] = $0.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: "LASER TGT LINE", text: binding(for: \\.laserTgtLine), isCompact: isCompact)
            EditableDetailRow(label: "PTL", text: binding(for: \\.ptl), isCompact: isCompact)
            EditableDetailRow(label: "GUN-TGT-LINE(MAX ORD)", text: binding(for: \\.gunTgtLine), isCompact: isCompact)
            EditableDetailRow(label: "MAX ORD", text: binding(for: \\.maxOrd), isCompact: isCompact)
            EditableDetailRow(label: "OTHER", text: binding(for: \\.text), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}
"""
    elif name == "RestrictionsDetailView":
        return """struct RestrictionsDetailView: View {
    @ObservedObject var jtacViewModel: JTACViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<Restrictions, String?>) -> Binding<String> {
        Binding(
            get: { jtacViewModel.report.restrictions?[keyPath: keyPath] ?? "" },
            set: { 
                if jtacViewModel.report.restrictions == nil { jtacViewModel.report.restrictions = Restrictions() }
                jtacViewModel.report.restrictions?[keyPath: keyPath] = $0.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: "DANGER CLOSE", text: binding(for: \\.dangerClose), isCompact: isCompact)
            EditableDetailRow(label: "FAH", text: binding(for: \\.fah), isCompact: isCompact)
            EditableDetailRow(label: "ACA’s", text: binding(for: \\.acas), isCompact: isCompact)
            EditableDetailRow(label: "TOT/TTT", text: binding(for: \\.totTtt), isCompact: isCompact)
            EditableDetailRow(label: "Lat/Alt", text: binding(for: \\.latAlt), isCompact: isCompact)
            EditableDetailRow(label: "POST LAUNCH ABORT", text: binding(for: \\.postLaunchAbort), isCompact: isCompact)
            EditableDetailRow(label: "OTHER", text: binding(for: \\.text), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}
"""
    elif name == "BDADetailView":
        return """struct BDADetailView: View {
    @ObservedObject var jtacViewModel: JTACViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<BDAData, String?>) -> Binding<String> {
        Binding(
            get: { jtacViewModel.report.bda?[keyPath: keyPath] ?? "" },
            set: { 
                if jtacViewModel.report.bda == nil { jtacViewModel.report.bda = BDAData() }
                jtacViewModel.report.bda?[keyPath: keyPath] = $0.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: "STATUS", text: binding(for: \\.status), isCompact: isCompact)
            EditableDetailRow(label: "SIZE", text: binding(for: \\.size), isCompact: isCompact)
            EditableDetailRow(label: "ACTIVITY", text: binding(for: \\.activity), isCompact: isCompact)
            EditableDetailRow(label: "LOCATION", text: binding(for: \\.location), isCompact: isCompact)
            EditableDetailRow(label: "TIME", text: binding(for: \\.time), isCompact: isCompact)
            EditableDetailRow(label: "REMARKS", text: binding(for: \\.remarks), isCompact: isCompact)
            EditableDetailRow(label: "OTHER", text: binding(for: \\.text), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}
"""
    return match.group(0)

pattern = r"struct (NineLineBriefDetailView|SafetyOfFlightDetailView|SituationUpdateDetailView|GamePlanDetailView|RemarksDetailView|RestrictionsDetailView|BDADetailView): View \{.*?\n\}\n"
new_text = re.sub(pattern, replacer, text, flags=re.DOTALL)

with open("/Users/pc/Documents/JTACXCode/JTAC/Views/NineLineView.swift", "w") as f:
    f.write(new_text)

