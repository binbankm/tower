import Foundation

struct PersistenceStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }

        if TowerTestIsolation.isEnabled {
            self.fileURL = TowerTestIsolation.directory.appendingPathComponent("state.json")
            return
        }
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.fileURL = baseURL
            .appendingPathComponent("Tower", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }

    func load() throws -> AppSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppSnapshot.self, from: data)
    }

    func save(_ snapshot: AppSnapshot) throws {
        let folderURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private var cloudBaselineURL: URL { fileURL.appendingPathExtension("cloud-base") }
    private var backupDirectory: URL { fileURL.deletingLastPathComponent().appendingPathComponent(fileURL.lastPathComponent + "-backups") }

    func cloudBaseline() throws -> AppSnapshot? { try PersistenceStore(fileURL: cloudBaselineURL).load() }
    func saveCloudBaseline(_ snapshot: AppSnapshot) throws { try PersistenceStore(fileURL: cloudBaselineURL).save(snapshot) }
    func clearCloudBaseline() throws {
        if FileManager.default.fileExists(atPath: cloudBaselineURL.path) { try FileManager.default.removeItem(at: cloudBaselineURL) }
    }
    func clearRecoveryData() throws {
        try clearCloudBaseline()
        if FileManager.default.fileExists(atPath: backupDirectory.path) { try FileManager.default.removeItem(at: backupDirectory) }
    }
    func backup(_ snapshot: AppSnapshot) throws {
        guard try !recoveryCopies().contains(where: { CloudSnapshotMerge.equal($0.snapshot, snapshot) }) else { return }
        try PersistenceStore(fileURL: backupDirectory.appendingPathComponent(UUID().uuidString + ".json")).save(snapshot)
        _ = try recoveryCopies()
    }
    func recoveryCopies() throws -> [CloudRecoveryCopy] {
        guard FileManager.default.fileExists(atPath: backupDirectory.path) else { return [] }
        let copies = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                try PersistenceStore(fileURL: url).load().map { CloudRecoveryCopy(id: "local-" + url.lastPathComponent, snapshot: $0) }
            }
            .sorted {
                let left = $0.snapshot.updatedAt ?? .distantPast, right = $1.snapshot.updatedAt ?? .distantPast
                return left == right ? $0.id < $1.id : left > right
            }
        let retained = Array(CloudRecoveryCopy.unique(copies).prefix(CloudSnapshotJournal.retentionLimit))
        let retainedIDs = Set(retained.map(\.id))
        for copy in copies where !retainedIDs.contains(copy.id) {
            try FileManager.default.removeItem(at: backupDirectory.appendingPathComponent(String(copy.id.dropFirst("local-".count))))
        }
        return retained
    }
}
