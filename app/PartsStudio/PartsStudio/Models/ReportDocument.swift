import Foundation

struct ReportDocument: Identifiable, Equatable {
    let id: String
    let title: String
    let filePath: String
    let date: String
    let body: String

    static func == (lhs: ReportDocument, rhs: ReportDocument) -> Bool {
        lhs.id == rhs.id
    }
}
