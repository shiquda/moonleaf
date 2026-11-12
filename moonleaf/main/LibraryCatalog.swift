//
//  LibraryCatalog.swift
//  moonleaf
//
//  Shared asset identity for favorites, playlists, sessions and history.
//  Relations store asset ids, not paths, so a rename that a bookmark can
//  resolve does not drop them.
//

import Foundation

struct AssetRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var bookmark: Data?
    var path: String
    var name: String
    var source: String
    var origin: String?
    var addedAt: Date
    var volumeUUID: String?
    var inode: Int?
}

struct NamedPlaylist: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var assetIDs: [UUID]
    var order: String
    var interval: String
}

struct FolderPool: Codable, Equatable {
    var path: String
    var includeSubdirectories: Bool
}

struct TargetSession: Codable, Equatable, Identifiable {
    var targetKey: String
    var assetID: UUID?
    var assetName: String?
    var path: String?
    var listKind: String?
    var playlistID: UUID?
    var folderPath: String?
    var includeSubdirectories: Bool?
    var rotationEnabled: Bool
    var paused: Bool
    var pauseReason: String?
    var order: String
    var interval: String
    var unavailable: Bool
    var provenance: String
    var lastRotatedAt: Date?

    var id: String { targetKey }
}

struct CatalogFile: Codable, Equatable {
    var assets: [AssetRecord] = []
    var favoriteIDs: [UUID] = []
    var playlists: [NamedPlaylist] = []
    var folderPool: FolderPool?
    var sessions: [TargetSession] = []
    var history: [HistoryEvent] = []
    var historyEnabled: Bool = true
    var futureSaveDirectory: String?
}

final class LibraryCatalog {
    static let shared = LibraryCatalog()
    static let fileURL = MoonleafConfigStore.configRoot.appendingPathComponent("catalog.json")

    private let queue = DispatchQueue(label: "com.naomisphere.moonleaf.catalog")
    private var file = CatalogFile()

    private init() {
        queue.sync {
            loadLocked()
            migrateFavoritesLocked()
        }
    }

    func snapshot() -> CatalogFile {
        queue.sync { file }
    }

    func mutate(_ body: (inout CatalogFile) -> Void) -> CatalogFile {
        queue.sync {
            body(&file)
            saveLocked()
            return file
        }
    }

    @discardableResult
    func ensureAsset(path: String, name: String?, source: String, origin: String?) -> AssetRecord {
        queue.sync {
            if let existing = file.assets.first(where: { $0.path == path }) {
                return existing
            }
            let url = URL(fileURLWithPath: path)
            let record = AssetRecord(
                id: UUID(),
                bookmark: bookmark(for: url),
                path: path,
                name: name ?? url.deletingPathExtension().lastPathComponent,
                source: source,
                origin: origin,
                addedAt: Date(),
                volumeUUID: volumeUUID(for: url),
                inode: inode(for: url)
            )
            file.assets.append(record)
            saveLocked()
            return record
        }
    }

    func resolvedAsset(_ id: UUID) -> (record: AssetRecord, url: URL)? {
        queue.sync {
            guard let index = file.assets.firstIndex(where: { $0.id == id }) else { return nil }
            guard let url = resolveLocked(index) else { return nil }
            return (file.assets[index], url)
        }
    }

    func asset(path: String) -> AssetRecord? {
        queue.sync { file.assets.first { $0.path == path } }
    }

    func favoritePaths() -> Set<String> {
        queue.sync {
            Set(file.favoriteIDs.compactMap { id in
                guard let index = file.assets.firstIndex(where: { $0.id == id }) else { return nil }
                return resolveLocked(index)?.path
            })
        }
    }

    func isFavorite(path: String) -> Bool {
        favoritePaths().contains(path)
    }

    func setFavorite(path: String, name: String, favorite: Bool) {
        queue.sync {
            let record = ensureAssetLocked(path: path, name: name, source: sourceFor(path), origin: nil)
            if favorite {
                if !file.favoriteIDs.contains(record.id) { file.favoriteIDs.append(record.id) }
            } else {
                file.favoriteIDs.removeAll { $0 == record.id }
            }
            saveLocked()
        }
    }

    func relocate(assetID: UUID, to url: URL) {
        queue.sync {
            guard let index = file.assets.firstIndex(where: { $0.id == assetID }) else { return }
            file.assets[index].path = url.path
            file.assets[index].name = url.deletingPathExtension().lastPathComponent
            file.assets[index].bookmark = bookmark(for: url)
            file.assets[index].volumeUUID = volumeUUID(for: url)
            file.assets[index].inode = inode(for: url)
            saveLocked()
        }
    }

    func playlists(containing assetID: UUID) -> [NamedPlaylist] {
        queue.sync { file.playlists.filter { $0.assetIDs.contains(assetID) } }
    }

    private func loadLocked() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode(CatalogFile.self, from: data) else { return }
        file = decoded
    }

    private func saveLocked() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        try? FileManager.default.createDirectory(at: MoonleafConfigStore.configRoot, withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    private func migrateFavoritesLocked() {
        guard file.favoriteIDs.isEmpty,
              let data = UserDefaults.standard.data(forKey: "moonleaf_favorites"),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return }
        for path in paths where FileManager.default.fileExists(atPath: path) {
            let record = ensureAssetLocked(path: path, name: nil, source: sourceFor(path), origin: nil)
            if !file.favoriteIDs.contains(record.id) { file.favoriteIDs.append(record.id) }
        }
        saveLocked()
    }

    @discardableResult
    private func ensureAssetLocked(path: String, name: String?, source: String, origin: String?) -> AssetRecord {
        if let existing = file.assets.first(where: { $0.path == path }) { return existing }
        let url = URL(fileURLWithPath: path)
        let record = AssetRecord(
            id: UUID(),
            bookmark: bookmark(for: url),
            path: path,
            name: name ?? url.deletingPathExtension().lastPathComponent,
            source: source,
            origin: origin,
            addedAt: Date(),
            volumeUUID: volumeUUID(for: url),
            inode: inode(for: url)
        )
        file.assets.append(record)
        return record
    }

    private func resolveLocked(_ index: Int) -> URL? {
        let record = file.assets[index]
        if let data = record.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                if url.path != record.path || stale {
                    file.assets[index].path = url.path
                    file.assets[index].name = url.deletingPathExtension().lastPathComponent
                    if stale { file.assets[index].bookmark = bookmark(for: url) }
                    saveLocked()
                }
                return url
            }
        }
        if FileManager.default.fileExists(atPath: record.path) {
            return URL(fileURLWithPath: record.path)
        }
        return nil
    }

    private func sourceFor(_ path: String) -> String {
        path.hasPrefix(MoonleafConfigStore.libraryRoot.path) ? "library" : "external"
    }

    private func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func volumeUUID(for url: URL) -> String? {
        try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }

    private func inode(for url: URL) -> Int? {
        let values = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (values?[.systemFileNumber] as? NSNumber)?.intValue
    }
}
