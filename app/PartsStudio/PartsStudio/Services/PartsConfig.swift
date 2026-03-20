import Foundation

/// Loads ~/.parts/config.yml and provides project paths to all stores.
struct PartsConfig {
    let projectName: String
    let projectPath: String
    let revision: String
    let ecoPath: String
    let bomPath: String
    let pcbPath: String
    let iqcPath: String
    let datasheetsPath: String
    let assemblyPath: String
    let fabReleasePath: String
    let apiURL: String
    let teamName: String
    let projectId: String

    static let shared = PartsConfig.load()

    private static func load() -> PartsConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(home)/.parts/config.yml"

        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return defaults(home: home)
        }

        let lines = content.components(separatedBy: "\n")
        var values: [String: String] = [:]
        var currentSection = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Detect section headers (no leading whitespace, ends with :, no value)
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && trimmed.hasSuffix(":") && !trimmed.contains(": ") {
                currentSection = String(trimmed.dropLast())
                continue
            }

            // Key: value pairs
            if let colonRange = trimmed.range(of: ": ") {
                let key = String(trimmed[..<colonRange.lowerBound])
                var val = String(trimmed[colonRange.upperBound...])
                // Strip quotes
                if val.hasPrefix("\"") && val.hasSuffix("\"") {
                    val = String(val.dropFirst().dropLast())
                }
                let fullKey = currentSection.isEmpty ? key : "\(currentSection).\(key)"
                values[fullKey] = val
            }
        }

        let projectPath = resolvePath(values["project.path"] ?? "~/Work/Consulting/nRF54H20-Main-Board", home: home)

        return PartsConfig(
            projectName: values["project.name"] ?? "nRF54H20 Main Board",
            projectPath: projectPath,
            revision: values["project.revision"] ?? "EVT2",
            ecoPath: "\(projectPath)/\(values["directories.eco"] ?? "ECO")",
            bomPath: "\(projectPath)/\(values["directories.bom"] ?? "BOM")",
            pcbPath: "\(projectPath)/\(values["directories.pcb"] ?? "PCB")",
            iqcPath: "\(projectPath)/\(values["directories.iqc"] ?? "IQC")",
            datasheetsPath: "\(projectPath)/\(values["directories.datasheets"] ?? "Datasheets")",
            assemblyPath: "\(projectPath)/\(values["directories.assembly"] ?? "PCB/EVT2/pdf_output")",
            fabReleasePath: "\(projectPath)/\(values["directories.fab_release"] ?? "PCB/EVT2/fab_release")",
            apiURL: values["api.url"] ?? "https://api.source.parts",
            teamName: values["team.name"] ?? "",
            projectId: values["team.project_id"] ?? ""
        )
    }

    private static func defaults(home: String) -> PartsConfig {
        let projectPath = "\(home)/Work/Consulting/nRF54H20-Main-Board"
        return PartsConfig(
            projectName: "nRF54H20 Main Board",
            projectPath: projectPath,
            revision: "EVT2",
            ecoPath: "\(projectPath)/ECO",
            bomPath: "\(projectPath)/BOM",
            pcbPath: "\(projectPath)/PCB",
            iqcPath: "\(projectPath)/IQC",
            datasheetsPath: "\(projectPath)/Datasheets",
            assemblyPath: "\(projectPath)/PCB/EVT2/pdf_output",
            fabReleasePath: "\(projectPath)/PCB/EVT2/fab_release",
            apiURL: "https://api.source.parts",
            teamName: "",
            projectId: ""
        )
    }

    private static func resolvePath(_ path: String, home: String) -> String {
        if path.hasPrefix("~/") {
            return home + String(path.dropFirst(1))
        }
        return path
    }
}
