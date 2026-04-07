import Foundation

struct Project: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var datasheetIds: [String]  // contentHash/filename keys

    init(name: String, datasheetIds: [String] = []) {
        self.id = UUID().uuidString
        self.name = name
        self.datasheetIds = datasheetIds
    }

    func contains(_ datasheet: CachedDatasheet) -> Bool {
        datasheetIds.contains(datasheet.id)
    }
}

struct ProjectsFile: Codable {
    let version: Int
    var projects: [Project]
}
