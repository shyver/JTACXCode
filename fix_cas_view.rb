import fileutils

file_path = "/Users/pc/Documents/JTACXCode/JTAC/Views/NineLineView.swift"
content = File.read(file_path)

content.gsub!(/struct CASCheckinDetailView: View \{.*?EditableDetailRow\(label: \"ABORT CODE\", text: abortCodeBinding, isCompact: isCompact\)\n        \}\n        .padding\(isCompact \? 8 : 12\)\n    \}/m, """struct CASCheckinDetailView: View {
    @ObservedObject var viewModel: MainViewModel
    var isCompact: Bool = false

    private func binding(for keyPath: WritableKeyPath<MissionData, String>) -> Binding<String> {
        Binding(
            get: { viewModel.missionData?[keyPath: keyPath] ?? \"\" },
            set: { viewModel.missionData?[keyPath: keyPath] = $0 }
        )
    }

    private func casBinding(for keyPath: WritableKeyPath<CASCheckin, String>) -> Binding<String> {
        Binding(
            get: { viewModel.missionData?.casCheckin[keyPath: keyPath] ?? \"\" },
            set: { viewModel.missionData?.casCheckin[keyPath: keyPath] = $0 }
        )
    }

    private var ordnanceBinding: Binding<String> {
        Binding(
            get: { viewModel.missionData?.ordnanceLoadout.joined(separator: \", \") ?? \"\" },
            set: { 
                let list = $0.components(separatedBy: \",\").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                viewModel.missionData?.ordnanceLoadout = list
            }
        )
    }

    // POS & ALT is not in struct, just fake state or string
    @State private var posAndAlt: String = \"\"

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            EditableDetailRow(label: \"CALLSIGN\", text: casBinding(for: \\.callsign), isCompact: isCompact)
            EditableDetailRow(label: \"MISSION\", text: binding(for: \\.campaignMissionName), isCompact: isCompact)
            EditableDetailRow(label: \"AIRCRAFT TYPE\", text: binding(for: \\.aircraftType), isCompact: isCompact)
            EditableDetailRow(label: \"POS & ALT\", text: $posAndAlt, isCompact: isCompact)
            EditableDetailRow(label: \"ORDNANCE\", text: ordnanceBinding, isCompact: isCompact)
            EditableDetailRow(label: \"PLAY TIME\", text: casBinding(for: \\.playTime), isCompact: isCompact)
            EditableDetailRow(label: \"CAPES\", text: casBinding(for: \\.capabilities), isCompact: isCompact)
            EditableDetailRow(label: \"LASER CODE\", text: casBinding(for: \\.laserCode), isCompact: isCompact)
            EditableDetailRow(label: \"VDL CODE\", text: casBinding(for: \\.vdlCode), isCompact: isCompact)
            EditableDetailRow(label: \"ABORT CODE\", text: casBinding(for: \\.abortCode), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 12)
    }
}""")

File.write(file_path, content)
