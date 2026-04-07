import Foundation
import Combine

/// Mirrors the Go storage package logic for reading ~/.cache/parts/datasheets/
class CacheService: ObservableObject {
    @Published var datasheets: [CachedDatasheet] = []
    @Published var aliases: [String: DatasheetAlias] = [:]

    static var cacheRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/parts/datasheets")
    }

    private var watcher: DispatchSourceFileSystemObject?

    init() {
        reload()
        startWatching()
    }

    deinit {
        watcher?.cancel()
    }

    func reload() {
        loadAliases()
        listCachedDatasheets()
    }

    // MARK: - Aliases (mirrors Go LoadAliases)

    private func loadAliases() {
        let aliasPath = Self.cacheRoot.appendingPathComponent("aliases.json")
        guard let data = try? Data(contentsOf: aliasPath) else {
            aliases = [:]
            return
        }
        do {
            aliases = try JSONDecoder().decode([String: DatasheetAlias].self, from: data)
        } catch {
            aliases = [:]
        }
    }

    // MARK: - List (mirrors Go ListCachedDatasheets)

    private func listCachedDatasheets() {
        let fm = FileManager.default
        let root = Self.cacheRoot

        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            datasheets = []
            return
        }

        // Build reverse alias lookup: contentHash/filename -> [aliasName]
        var hashToAliases: [String: [String]] = [:]
        for (name, alias) in aliases {
            let key = "\(alias.contentHash)/\(alias.filename)"
            hashToAliases[key, default: []].append(name)
        }

        var results: [CachedDatasheet] = []

        for dir in entries {
            guard dir.lastPathComponent.hasPrefix("sha256_") else { continue }
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }

            let hash = String(dir.lastPathComponent.dropFirst("sha256_".count))

            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
                continue
            }

            for file in files {
                let fileIsDir = (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if fileIsDir { continue }

                let filename = file.lastPathComponent
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                let key = "\(hash)/\(filename)"
                let fileAliases = hashToAliases[key] ?? []

                results.append(CachedDatasheet(
                    contentHash: hash,
                    filename: filename,
                    path: file.path,
                    size: Int64(size),
                    aliases: fileAliases
                ))
            }
        }

        // Sort: aliased first, then by filename
        results.sort { a, b in
            if !a.aliases.isEmpty && b.aliases.isEmpty { return true }
            if a.aliases.isEmpty && !b.aliases.isEmpty { return false }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }

        datasheets = results
    }

    // MARK: - Resolve alias (mirrors Go ResolveAlias)

    func resolveAlias(_ name: String) -> (contentHash: String, filename: String)? {
        guard let alias = aliases[name] else { return nil }
        return (alias.contentHash, alias.filename)
    }

    // MARK: - Import PDF to cache (mirrors Go CacheDatasheet)

    func importAndCache(path: String) {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return }

        // SHA256 hash, first 16 hex chars (mirrors Go ContentHash)
        let hash = data.sha256Prefix16()
        let filename = url.lastPathComponent

        let destDir = Self.cacheRoot.appendingPathComponent("sha256_\(hash)")
        let destFile = destDir.appendingPathComponent(filename)

        let fm = FileManager.default
        try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: destFile.path) {
            try? fm.copyItem(at: url, to: destFile)
        }
    }

    // MARK: - File system watcher

    private func startWatching() {
        let root = Self.cacheRoot
        let fm = FileManager.default
        if !fm.fileExists(atPath: root.path) {
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        }

        let fd = open(root.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.reload()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        watcher = source
    }
}

// MARK: - SHA256 helper

import CryptoKit

extension Data {
    func sha256Prefix16() -> String {
        let digest = SHA256.hash(data: self)
        let bytes = Array(digest.prefix(8))  // 8 bytes = 16 hex chars
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
