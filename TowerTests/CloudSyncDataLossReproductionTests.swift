import XCTest
@testable import Tower

/// Empty devices must not publish destructive replacement snapshots.
@MainActor
final class CloudSyncDataLossReproductionTests: XCTestCase {
    func testUntouchedEmptyMacDownloadsPopulatedPhoneSnapshot() async throws {
        try await runEmptyMacScenario(editBeforeEnabling: false)
    }

    func testEmptyMacSettingsEditCannotClearCloudOrPhone() async throws {
        try await runEmptyMacScenario(editBeforeEnabling: true)
    }

    func testCurrentLocalVersionCanBeChosenBeforeAnyBackupExists() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = AppModel(persistence: PersistenceStore(fileURL: folder.appendingPathComponent("local.json")), cloudSync: CloudSyncStore(fileURL: folder.appendingPathComponent("cloud.json")), arguments: [])
        model.setConfigurationName("Keep this device")
        await model.loadCloudRecoveryCopies()
        let current = try XCTUnwrap(model.cloudRecoveryCopies.first { $0.id == "current-local" })
        XCTAssertEqual(current.snapshot.configurationName, "Keep this device")
        await model.restoreCloudCopy(current)
        XCTAssertNil(model.cloudSyncIssue)
        await model.loadCloudRecoveryCopies()
        XCTAssertEqual(model.cloudRecoveryCopies.count, 1)
    }

    func testForegroundChecksOnceUntilBackgroundAndManualSyncStillWorks() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let previous = CloudSyncPreference.isEnabled()
        CloudSyncPreference.setEnabled(false)
        defer { CloudSyncPreference.setEnabled(previous) }
        let cloud = CloudSyncStore(fileURL: folder.appendingPathComponent("cloud.json"))
        let store = PersistenceStore(fileURL: folder.appendingPathComponent("local.json"))
        let model = AppModel(persistence: store, cloudSync: cloud, arguments: [])
        await model.setICloudSyncEnabled(true)
        await model.performForegroundOpenWork()
        let downloaded = try await cloud.download()
        var remote = try XCTUnwrap(downloaded)
        remote.configurationName = "Changed on Mac"
        try await cloud.upload(remote)
        await model.performForegroundOpenWork()
        XCTAssertNotEqual(model.configurationName, "Changed on Mac")
        model.didEnterBackground()
        await model.performForegroundOpenWork()
        XCTAssertEqual(model.configurationName, "Changed on Mac")
        remote.configurationName = "Manual update"
        try await cloud.upload(remote)
        await model.synchronizeWithCloud(showResult: true)
        XCTAssertEqual(model.configurationName, "Manual update")
        await model.loadCloudRecoveryCopies()
        let copies = model.cloudRecoveryCopies
        for (index, copy) in copies.enumerated() {
            XCTAssertFalse(copies.dropFirst(index + 1).contains { CloudSnapshotMerge.equal(copy.snapshot, $0.snapshot) })
        }
        await model.setICloudSyncEnabled(false)
    }

    func testRestoringUndatedSnapshotCreatesBackup() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersistenceStore(fileURL: folder.appendingPathComponent("local.json"))
        try store.save(AppSnapshot(subscriptions: [], nodes: [], selectedPresetID: "default", selectedTarget: .surge))
        let model = AppModel(persistence: store, cloudSync: CloudSyncStore(fileURL: folder.appendingPathComponent("cloud.json")), arguments: [])
        await model.loadCloudRecoveryCopies()
        let current = try XCTUnwrap(model.cloudRecoveryCopies.first)
        await model.restoreCloudCopy(current)
        XCTAssertNil(model.cloudSyncIssue)
        XCTAssertEqual(try store.recoveryCopies().count, 1)
    }

    private func runEmptyMacScenario(editBeforeEnabling: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let previous = CloudSyncPreference.isEnabled()
        CloudSyncPreference.setEnabled(false)
        defer { CloudSyncPreference.setEnabled(previous) }
        let cloud = CloudSyncStore(fileURL: folder.appendingPathComponent("cloud.json"))
        let phoneStore = PersistenceStore(fileURL: folder.appendingPathComponent("phone.json"))
        let scheme = try RuleSchemeParser().parse(text: """
        [Proxy Group]
        Main = select, DIRECT
        [Rule]
        DOMAIN,example.com,Main
        FINAL,Main
        """, id: "owned-rules", name: "Owned Rules", summary: "Fixture")
        let populated = AppSnapshot(
            subscriptions: [SubscriptionSource(name: "Fixture", urlString: "https://example.invalid/sub")],
            nodes: [ProxyNode(kind: .trojan, name: "Fixture", server: "example.invalid", port: 443, password: "fixture", rawURI: "")],
            selectedPresetID: scheme.id, selectedTarget: .surge,
            importedSchemes: [scheme], updatedAt: Date.now.addingTimeInterval(-3600)
        )
        try phoneStore.save(populated)
        try await cloud.upload(populated)
        let phone = AppModel(persistence: phoneStore, cloudSync: cloud, arguments: [], clientPlatform: .phone)
        let mac = AppModel(persistence: PersistenceStore(fileURL: folder.appendingPathComponent("mac.json")), cloudSync: cloud, arguments: [], clientPlatform: .mac)
        XCTAssertEqual(phone.nodes.count, 1)
        XCTAssertEqual(phone.importedSchemes.first?.groups.count, 1)
        XCTAssertEqual(phone.importedSchemes.first?.rulesets.count, 2)
        XCTAssertTrue(mac.nodes.isEmpty)
        if editBeforeEnabling { mac.setConfigurationName("My Mac") }
        await mac.setICloudSyncEnabled(true)
        let remote = try await cloud.download()
        XCTAssertEqual(remote?.nodes.count, 1)
        await phone.setICloudSyncEnabled(true)
        XCTAssertEqual(phone.nodes.count, 1)
        XCTAssertEqual(phone.subscriptions.count, 1)
        XCTAssertEqual(phone.importedSchemes.count, 1)
        XCTAssertEqual(try phoneStore.load()?.nodes.count, 1)
        await phone.setICloudSyncEnabled(false)
        await mac.setICloudSyncEnabled(false)
    }
}
