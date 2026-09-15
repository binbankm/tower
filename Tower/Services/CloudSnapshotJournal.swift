import Foundation

struct CloudRecoveryCopy: Identifiable, Sendable {
    let id: String
    let snapshot: AppSnapshot

    /// Keep caller ordering (current local first, then newest history). Dates
    /// describe versions, not configuration content, and do not affect equality.
    static func unique(_ copies: [CloudRecoveryCopy]) -> [CloudRecoveryCopy] {
        var fingerprints = Set<Data>()
        return copies.filter { copy in
            var snapshot = copy.snapshot
            snapshot.updatedAt = nil
            guard let content = try? CloudSnapshotMerge.data(snapshot) else { return true }
            return fingerprints.insert(content).inserted
        }
    }
}

/// Immutable commits preserve concurrent writes across machines. File coordination
/// alone only serializes this machine's iCloud cache, not every device's cache.
struct CloudSnapshotJournal {
    static let retentionLimit = 10
    struct Commit: Codable {
        let id: String
        let parents: [String]
        let snapshot: AppSnapshot?
    }
    let directory: URL

    func commits() throws -> [String: Commit] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey])
        var result: [String: Commit] = [:]
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        for file in files {
            if file.pathExtension == "icloud" {
                let name = file.deletingPathExtension().lastPathComponent
                let target = directory.appendingPathComponent(name.hasPrefix(".") ? String(name.dropFirst()) : name)
                try FileManager.default.startDownloadingUbiquitousItem(at: target)
                throw CloudSyncError.downloading
            }
            guard ["json", "pruned"].contains(file.pathExtension) else { continue }
            try Self.requireDownloaded(file)
            let commit = try decoder.decode(Commit.self, from: Data(contentsOf: file))
            guard UUID(uuidString: commit.id) != nil, file.deletingPathExtension().lastPathComponent == commit.id else { throw CloudSyncError.conflict }
            // A pruning marker wins if iCloud delivers an old full file again.
            if file.pathExtension == "pruned" || result[commit.id] == nil {
                result[commit.id] = commit
            }
        }
        // Missing parents may simply still be travelling through iCloud.
        guard result.values.allSatisfy({ $0.parents.allSatisfy { result[$0] != nil } }) else { throw CloudSyncError.downloading }
        return result
    }

    static func requireDownloaded(_ file: URL) throws {
        let values = try file.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current {
            try FileManager.default.startDownloadingUbiquitousItem(at: file)
            throw CloudSyncError.downloading
        }
    }

    func heads(_ commits: [String: Commit]) -> [String] {
        let parents = Set(commits.values.flatMap(\.parents))
        return commits.keys.filter { !parents.contains($0) }.sorted()
    }

    func snapshot(_ commits: [String: Commit]) throws -> AppSnapshot? {
        let ids = heads(commits)
        guard let first = ids.first else {
            if !commits.isEmpty { throw CloudSyncError.conflict }
            return nil
        }
        guard var merged = commits[first]?.snapshot else { throw CloudSyncError.conflict }
        var common = try ancestors(first, commits: commits, visiting: [])
        for id in ids.dropFirst() {
            common.formIntersection(try ancestors(id, commits: commits, visiting: []))
            // A common ancestor closest to the heads is a shared baseline.
            let closest = common.filter { candidate in
                !common.contains { other in
                    other != candidate && ((try? ancestors(other, commits: commits, visiting: []).contains(candidate)) ?? false)
                }
            }.sorted()
            guard closest.count <= 1 else { throw CloudSyncError.conflict }
            guard let remote = commits[id]?.snapshot else { throw CloudSyncError.conflict }
            let base = closest.first.flatMap { commits[$0]?.snapshot }
            // A pruned baseline is not a first sync. Never bootstrap-merge it:
            // doing so could resurrect deleted nodes from a long-offline device.
            if !closest.isEmpty && base == nil { throw CloudSyncError.conflict }
            merged = try CloudSnapshotMerge.merge(local: merged, remote: remote, base: base)
        }
        return merged
    }

    private func ancestors(_ id: String, commits: [String: Commit], visiting: Set<String>) throws -> Set<String> {
        guard !visiting.contains(id), let commit = commits[id] else { throw CloudSyncError.conflict }
        var visiting = visiting; visiting.insert(id)
        var result: Set<String> = [id]
        for parent in commit.parents { result.formUnion(try ancestors(parent, commits: commits, visiting: visiting)) }
        return result
    }

    func append(_ snapshot: AppSnapshot, parents: [String]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = Commit(id: UUID().uuidString, parents: parents, snapshot: snapshot)
        try write(record, extension: "json")
    }

    /// Remove configuration payloads, retaining only IDs and parent links.
    /// Mark-before-delete makes interrupted cleanup and reordered cloud delivery safe.
    func prune() throws {
        let records = try commits()
        let liveHeads = Set(heads(records))
        let full = records.values.filter { $0.snapshot != nil }.sorted { lhs, rhs in
            let ld = lhs.snapshot?.updatedAt ?? .distantPast
            let rd = rhs.snapshot?.updatedAt ?? .distantPast
            return ld == rd ? lhs.id < rhs.id : ld > rd
        }
        // Unresolved concurrent branches must never be silently discarded.
        guard liveHeads.count <= Self.retentionLimit else { throw CloudSyncError.conflict }
        var keep = liveHeads
        for record in full where keep.count < Self.retentionLimit { keep.insert(record.id) }
        for record in full where !keep.contains(record.id) {
            try write(Commit(id: record.id, parents: record.parents, snapshot: nil), extension: "pruned")
        }
        let pruned = try commits().values.filter { $0.snapshot == nil }
        for record in pruned {
            let url = directory.appendingPathComponent(record.id + ".json")
            var error: NSError?
            var deletionError: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { target in
                do {
                    if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                } catch { deletionError = error }
            }
            if let error { throw error }
            if let deletionError { throw deletionError }
        }
    }

    private func write(_ record: Commit, extension suffix: String) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let target = directory.appendingPathComponent(record.id + "." + suffix)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: [], error: &coordinationError) { url in
            do { try data.write(to: url, options: [.atomic, .completeFileProtection]) }
            catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
