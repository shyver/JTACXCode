import Foundation

enum AppScreen {
    case home
    case newMission
    case main
    case liveTranscript
    case nineLine
    case map
    case database
    case settings
    case archive
}

enum SectionType: String {
    case liveTranscript = "Live Radio Transcript"
    case nineLine = "9 Line"
    case map = "Map View"
}
