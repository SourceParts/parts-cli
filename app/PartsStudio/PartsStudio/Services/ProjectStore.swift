import Foundation

/// Manages projects that group datasheets together.
/// Stored at ~/.cache/parts/datasheets/projects.json
class ProjectStore: ObservableObject {
    @Published var projects: [Project] = []
    @Published var selectedProject: Project?

    private var projectsPath: URL {
        CacheService.cacheRoot.appendingPathComponent("projects.json")
    }

    init() {
        load()
    }

    // MARK: - Load / Save

    func load() {
        guard let data = try? Data(contentsOf: projectsPath) else {
            projects = []
            return
        }
        do {
            let file = try JSONDecoder().decode(ProjectsFile.self, from: data)
            projects = file.projects
        } catch {
            projects = []
        }
    }

    func save() {
        let file = ProjectsFile(version: 1, projects: projects)
        guard let data = try? JSONEncoder.prettyPrinted.encode(file) else { return }
        try? data.write(to: projectsPath, options: .atomic)
    }

    // MARK: - CRUD

    func createProject(name: String) -> Project {
        let project = Project(name: name)
        projects.append(project)
        save()
        return project
    }

    func deleteProject(id: String) {
        projects.removeAll { $0.id == id }
        if selectedProject?.id == id {
            selectedProject = nil
        }
        save()
    }

    func renameProject(id: String, name: String) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].name = name
        if selectedProject?.id == id {
            selectedProject = projects[index]
        }
        save()
    }

    func addDatasheet(_ datasheet: CachedDatasheet, to projectId: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        if !projects[index].datasheetIds.contains(datasheet.id) {
            projects[index].datasheetIds.append(datasheet.id)
            if selectedProject?.id == projectId {
                selectedProject = projects[index]
            }
            save()
        }
    }

    func removeDatasheet(_ datasheet: CachedDatasheet, from projectId: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[index].datasheetIds.removeAll { $0 == datasheet.id }
        if selectedProject?.id == projectId {
            selectedProject = projects[index]
        }
        save()
    }

    func datasheetsForProject(_ project: Project, allDatasheets: [CachedDatasheet]) -> [CachedDatasheet] {
        allDatasheets.filter { project.datasheetIds.contains($0.id) }
    }
}
