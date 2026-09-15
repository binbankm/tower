import XCTest

@MainActor
final class CloudRecoveryInteractionTests: XCTestCase {
    func testRecoveryPageRestoresConfigurationAndPreservesBackup() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["TOWER_UNIT_TEST_RUN"] = "1"
        app.launchArguments = ["-hasSeenWelcome", "YES", "--tab=export", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        defer { app.terminate() }
        app.tabBars.buttons.element(boundBy: 2).tap()
        let settings = app.buttons["open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let recovery = app.buttons["恢复同步备份"]
        for _ in 0..<8 where !recovery.isHittable { app.swipeUp() }
        XCTAssertTrue(recovery.isHittable)
        recovery.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "个节点")).firstMatch.waitForExistence(timeout: 10))
        let copies = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "个节点"))
        XCTAssertTrue(copies.firstMatch.waitForExistence(timeout: 5))
        copies.firstMatch.tap()
        let alert = app.alerts["恢复这份配置？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let confirmation = alert.buttons["恢复"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let confirmationShot = XCTAttachment(screenshot: app.screenshot())
        confirmationShot.name = "cloud-restore-confirmation"
        confirmationShot.lifetime = .keepAlways
        add(confirmationShot)
        confirmation.tap()
        let backupCreated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in copies.count >= 2 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [backupCreated], timeout: 10), .completed)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "isolated-cloud-recovery-sheet"
        shot.lifetime = .keepAlways
        add(shot)
        app.navigationBars["恢复同步备份"].buttons["完成"].tap()
        XCTAssertTrue(recovery.waitForExistence(timeout: 5))
    }
}
