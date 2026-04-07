import Foundation

/// Loads ~/.parts/config.yml and provides project paths to all stores.
struct PartsConfig {
    let projectName: String
    let projectPath: String
    let revision: String
    let ecoPath: String
    let reportsPath: String
    let bomPath: String
    let pcbPath: String
    let iqcPath: String
    let datasheetsPath: String
    let assemblyPath: String
    let fabReleasePath: String
    let modelsPath: String
    let apiURL: String
    let teamName: String
    let projectId: String

    static var shared = PartsConfig.load()

    /// Re-read ~/.parts/config.yml and update the shared instance.
    @discardableResult
    static func reload() -> PartsConfig {
        shared = load()
        return shared
    }

    /// Write a new revision for the active project into ~/.parts/config.yml and reload.
    @discardableResult
    static func setRevision(_ newRevision: String) -> PartsConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(home)/.parts/config.yml"
        guard var content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return shared
        }

        // Find the active project's revision line and replace it
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var inActiveProject = false
        let activeName = shared.projectName

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect project list entry start
            if trimmed.hasPrefix("- name: ") {
                let val = trimmed.replacingOccurrences(of: "- name: ", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                inActiveProject = (val == activeName)
            }

            // Replace revision line for the active project
            if inActiveProject && trimmed.hasPrefix("revision: ") {
                let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
                result.append("\(indent)revision: \"\(newRevision)\"")
                inActiveProject = false
                continue
            }

            result.append(line)
        }

        try? result.joined(separator: "\n").write(toFile: configPath, atomically: true, encoding: .utf8)
        return reload()
    }

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

        // Parse projects list to resolve the active project's path and revision
        let activeProjectName = values["projects.active_project"] ?? ""
        if !activeProjectName.isEmpty {
            var inProjects = false
            var entry: [String: String] = [:]
            var matched: [String: String]?

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                if trimmed == "projects:" { inProjects = true; continue }
                if inProjects && !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                    if entry["name"] == activeProjectName { matched = entry }
                    inProjects = false; continue
                }
                guard inProjects else { continue }

                if trimmed.hasPrefix("- ") {
                    if entry["name"] == activeProjectName { matched = entry }
                    entry = [:]
                    let rest = String(trimmed.dropFirst(2))
                    if let r = rest.range(of: ": ") {
                        let k = String(rest[..<r.lowerBound])
                        var v = String(rest[r.upperBound...])
                        if v.hasPrefix("\"") && v.hasSuffix("\"") { v = String(v.dropFirst().dropLast()) }
                        entry[k] = v
                    }
                } else if let r = trimmed.range(of: ": ") {
                    let k = String(trimmed[..<r.lowerBound])
                    var v = String(trimmed[r.upperBound...])
                    if v.hasPrefix("\"") && v.hasSuffix("\"") { v = String(v.dropFirst().dropLast()) }
                    entry[k] = v
                }
            }
            if inProjects && entry["name"] == activeProjectName { matched = entry }

            if let proj = matched {
                if let p = proj["path"] { values["project.path"] = p }
                if let r = proj["revision"] { values["project.revision"] = r }
                if let n = proj["name"] { values["project.name"] = n }
            }
        }

        let projectPath = resolvePath(values["project.path"] ?? "~/Work/Consulting/nRF54H20-Main-Board", home: home)
        let rev = values["project.revision"] ?? "EVT2"

        return PartsConfig(
            projectName: values["project.name"] ?? "nRF54H20 Main Board",
            projectPath: projectPath,
            revision: rev,
            ecoPath: "\(projectPath)/\(values["directories.eco"] ?? "ECO")",
            reportsPath: "\(projectPath)/\(values["directories.reports"] ?? "Reports")",
            bomPath: "\(projectPath)/\(values["directories.bom"] ?? "BOM")",
            pcbPath: "\(projectPath)/\(values["directories.pcb"] ?? "PCB")",
            iqcPath: "\(projectPath)/\(values["directories.iqc"] ?? "IQC")",
            datasheetsPath: "\(projectPath)/\(values["directories.datasheets"] ?? "Datasheets")",
            assemblyPath: "\(projectPath)/\(values["directories.assembly"] ?? "PCB/\(rev)/pdf_output")",
            fabReleasePath: "\(projectPath)/\(values["directories.fab_release"] ?? "PCB/\(rev)/fab_release")",
            modelsPath: "\(projectPath)/\(values["directories.3d_models"] ?? "PCB/\(rev)/3D_Models")",
            apiURL: values["api.url"] ?? "https://api.source.parts",
            teamName: values["team.name"] ?? "",
            projectId: values["team.project_id"] ?? ""
        )
    }

    private static func defaults(home: String) -> PartsConfig {
        let projectPath = "\(home)/Work/Consulting/nRF54H20-Main-Board"
        let rev = "EVT2"
        return PartsConfig(
            projectName: "nRF54H20 Main Board",
            projectPath: projectPath,
            revision: rev,
            ecoPath: "\(projectPath)/ECO",
            reportsPath: "\(projectPath)/Reports",
            bomPath: "\(projectPath)/BOM",
            pcbPath: "\(projectPath)/PCB",
            iqcPath: "\(projectPath)/IQC",
            datasheetsPath: "\(projectPath)/Datasheets",
            assemblyPath: "\(projectPath)/PCB/\(rev)/pdf_output",
            fabReleasePath: "\(projectPath)/PCB/\(rev)/fab_release",
            modelsPath: "\(projectPath)/PCB/\(rev)/3D_Models",
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
