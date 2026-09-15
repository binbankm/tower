import Foundation

/// Anywhere's node-URI dialect, verified against upstream 9ae49a73a0cf.
/// This client imports subscriptions, not Tower's policy groups and rules.
enum AnywhereExport {
    private static let fingerprints = [
        "chrome": "chrome_120", "firefox": "firefox_120", "safari": "safari_26",
        "edge": "edge_106"
    ]
    private static let nativeFingerprints: Set<String> = [
        "chrome_133", "chrome_120", "chrome_106", "firefox_148", "firefox_120",
        "safari_26", "edge_106", "non_browser"
    ]

    static func supports(_ node: ProxyNode) -> Bool {
        if node.kind == .vless, UUID(uuidString: node.uuid ?? "") == nil { return false }
        // The subscription parser ignores pins, per-node insecure and UDP-off.
        // Never silently weaken these requirements or replace them with defaults.
        guard (node.certificateFingerprint ?? "").isEmpty,
              !node.skipCertificateVerification,
              node.udpRelayEnabled != false,
              (node.portHopping ?? "").isEmpty,
              (node.plugin ?? "").isEmpty else { return false }
        if let fp = node.fingerprint, !fp.isEmpty,
           fingerprints[fp.lowercased()] == nil, !nativeFingerprints.contains(fp) { return false }
        if node.usesReality && node.kind != .vless { return false }
        let transport = node.transport?.lowercased() ?? "tcp"
        if node.kind != .vless && !["", "tcp"].contains(transport) { return false }
        switch node.kind {
        case .shadowsocks:
            return !node.tls && (node.obfs ?? "none") == "none"
                && ["aes-128-gcm", "aes-256-gcm", "chacha20-ietf-poly1305", "chacha20-poly1305",
                    "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm",
                    "2022-blake3-chacha20-poly1305", "none"].contains(node.cipher ?? "")
                && node.password != nil
        case .socks5:
            return !node.tls
        case .hysteria2:
            return (node.alpn ?? "").isEmpty
                && ["", "none", "salamander", "gecko"].contains(node.obfs?.lowercased() ?? "")
        default:
            return true
        }
    }

    static func link(for node: ProxyNode) -> String {
        let canonical = ProxyNodeShareLinkGenerator().canonicalLink(for: node)
        guard node.kind != .shadowsocks,
              var url = URLComponents(string: canonical) else { return canonical }
        var items = url.queryItems ?? []
        let aliases = ["idle-session-check-interval": "ici", "idle-session-timeout": "it", "min-idle-session": "mis"]
        items = items.map { item in
            if node.kind == .vless, node.transport == "grpc", item.name == "host" {
                return URLQueryItem(name: "authority", value: item.value)
            }
            if let alias = aliases[item.name] { return URLQueryItem(name: alias, value: item.value) }
            if item.name == "fp", let value = item.value, let mapped = fingerprints[value.lowercased()] {
                return URLQueryItem(name: "fp", value: mapped)
            }
            return item
        }
        // SOCKS5's parser expects host:port with no URI query suffix.
        if node.kind == .socks5 { items = [] }
        if node.kind == .vless, let flow = node.flow, !flow.isEmpty,
           !items.contains(where: { $0.name == "flow" }) {
            items.append(URLQueryItem(name: "flow", value: flow))
        }
        if node.kind == .hysteria2 {
            if let up = node.upMbps { items.append(URLQueryItem(name: "upmbps", value: String(up))) }
            if let down = node.downMbps { items.append(URLQueryItem(name: "downmbps", value: String(down))) }
        }
        url.queryItems = items.isEmpty ? nil : items
        return url.string ?? canonical
    }
}
