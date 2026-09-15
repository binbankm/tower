import XCTest
@testable import Tower

final class Issue33ReproductionTests: XCTestCase {
    func testLegacyRestoreKeepsSelectedNodesAndGroupTypes() throws {
        let text = """
        proxy-providers:
          all-proxies: {type: http, url: 'https://example.com/sub'}
        proxy-groups:
          - {name: Manual, type: select, use: [all-proxies]}
          - {name: Auto, type: url-test, use: [all-proxies], interval: 300}
          - {name: HK, type: select, use: [all-proxies], filter: HK}
        rules: ['MATCH,Manual']
        """
        let parser = RuleSchemeParser()
        let fresh = try parser.parse(text: text, id: "issue33", name: "Self-Configuration", summary: "", useSelectedNodes: true)
        let nodes = (0..<370).map { ProxyNode(kind: .trojan, name: $0 < 55 ? "HK \($0)" : "US \($0)", server: "example.com", port: 443, password: "test", rawURI: "") }
        // A legacy persisted group lacks sourceType. Regional metadata may already
        // be current, e.g. after a separate edit/import migration.
        var legacy = fresh
        legacy.groups = fresh.groups.map { group in
            if group.name == "HK" { return group }
            return RuleSchemeGroup(name: group.name, kind: group.kind, members: group.members,
                                   interval: group.interval)
        }
        let restored = parser.restoringLegacySmartGroups(in: legacy)
        XCTAssertEqual(try NodeNameFilterMatcher.preview(".*", candidates: nodes.map { [$0.name] }, caseInsensitive: false).count, 370)
        for target in [ClientTarget.clash, .singBox, .shadowrocket] {
            let before = ConfigurationGenerator().generate(nodes: nodes, scheme: fresh, target: target)
            let after = ConfigurationGenerator().generate(nodes: nodes, scheme: restored, target: target)
            XCTAssertEqual(before.content, after.content, target.rawValue)
        }
        XCTAssertNil(restored.groups[0].parameters?["use"])
        XCTAssertEqual(parser.restoringLegacySmartGroups(in: restored), restored)
    }
    func testAlreadyMigratedTemplateIsRepairedButRealBindingsRemain() throws {
        let source = """
        proxy-groups:
          - {name: Manual, type: select, use: [all-proxies]}
        rules: ['MATCH,Manual']
        """
        let parser = RuleSchemeParser()
        let broken = try parser.parse(text: source, id: "legacy", name: "Legacy", summary: "")
        XCTAssertNotNil(broken.groups[0].sourceType)
        let repaired = parser.restoringLegacySmartGroups(in: broken)
        XCTAssertNil(repaired.groups[0].parameters?["use"])
        let bound = try parser.parse(text: "proxy-providers:\n  all-proxies: {type: http, url: 'https://example.com/sub'}\n" + source,
                                     id: "bound", name: "Bound", summary: "")
        XCTAssertEqual(parser.restoringLegacySmartGroups(in: bound), bound)
    }

}
