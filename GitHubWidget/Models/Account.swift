import Foundation

struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var username: String
    var orgFilter: String

    var keychainKey: String { "github_pat_\(id.uuidString)" }
}
