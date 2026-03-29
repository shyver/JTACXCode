import Foundation

let jsonString = """
{
  "nineLine": {
    "ip": "",
    "heading": "",
    "distance": "",
    "targetElevation": "",
    "targetDescription": "",

    "targetMark": "",
    "friendlies": "",
    "remarksLine": ""
  }
}
"""

struct NL: Codable {
    var ip: String?
    var heading: String?
    var distance: String?
    var targetElevation: String?
    var targetDescription: String?
    var targetMark: String?
    var friendlies: String?
    var egress: String?
    var remarksLine: String?
}

struct Top: Codable {
    var nineLine: NL?
}

let data = jsonString.data(using: .utf8)!
do {
    let top = try JSONDecoder().decode(Top.self, from: data)
    print("Success: \(top)")
} catch {
    print("Error: \(error)")
}
