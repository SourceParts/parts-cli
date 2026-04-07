import Foundation

enum ECODocType: String, Codable {
    case ecn = "ECN"
    case ecr = "ECR"
    case eco = "ECO"
}

struct ECODocument: Identifiable, Hashable {
    let id: String           // e.g. "ECN-027"
    let type: ECODocType
    let title: String
    let severity: String     // CRITICAL, HIGH, MEDIUM, LOW
    let status: String       // OPEN, IN REVIEW, APPROVED, etc.
    let filePath: String
    let body: String         // Full markdown content

    var severityColor: String {
        switch severity.uppercased() {
        case "CRITICAL": return "red"
        case "HIGH": return "orange"
        case "MEDIUM": return "yellow"
        case "LOW": return "green"
        default: return "gray"
        }
    }
}
