import SwiftUI

struct CountryNodeExportGroup: Identifiable {
    let code: String
    let title: String
    let nodes: [ProxyNode]

    var id: String { code }
}

struct ProtocolNodeExportGroup: Identifiable {
    let kind: ProxyKind
    let nodes: [ProxyNode]

    var id: ProxyKind { kind }
}

enum NodeExportGroupBuilder {
    static func countryGroups(
        nodes: [ProxyNode],
        countryCode: (ProxyNode) -> String?
    ) -> [CountryNodeExportGroup] {
        var groupedNodes: [String: [ProxyNode]] = [:]
        for node in nodes {
            guard let code = countryCode(node)?.uppercased() else { continue }
            groupedNodes[code, default: []].append(node)
        }

        return groupedNodes.map { code, nodes in
            CountryNodeExportGroup(
                code: code,
                title: AppLocalization.regionName(for: code),
                nodes: nodes
            )
        }.sorted { lhs, rhs in
            if lhs.nodes.count != rhs.nodes.count {
                return lhs.nodes.count > rhs.nodes.count
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    static func protocolGroups(nodes: [ProxyNode]) -> [ProtocolNodeExportGroup] {
        Dictionary(grouping: nodes, by: \.kind)
            .map { ProtocolNodeExportGroup(kind: $0.key, nodes: $0.value) }
            .sorted { lhs, rhs in
                if lhs.nodes.count != rhs.nodes.count {
                    return lhs.nodes.count > rhs.nodes.count
                }
                return lhs.kind.title.localizedStandardCompare(rhs.kind.title) == .orderedAscending
            }
    }
}

enum NodeExportGroupSelectionState: Equatable {
    case none
    case partial
    case all

    init(includedCount: Int, totalCount: Int) {
        if totalCount > 0, includedCount >= totalCount {
            self = .all
        } else if includedCount > 0 {
            self = .partial
        } else {
            self = .none
        }
    }

    /// A group remains selected while it still contributes at least one node.
    /// The count beside a partial group communicates the exceptions; removing
    /// the checkmark as soon as one child is disabled incorrectly reads as if
    /// the entire country or protocol were excluded.
    var isMenuSelected: Bool {
        self != .none
    }
}

struct NodeFilterSections: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var searchText: String
    @Binding var showsNameFilter: Bool

    var body: some View {
        // Filtering used to run once for the rows, once for the empty check,
        // once for the header count, once for the select-all state and once for
        // its disabled state — five passes over every node, each resolving a
        // display name and running four case-insensitive searches, on every
        // keystroke in the search field.
        let filteredNodes = self.filteredNodes
        let includedFilteredNodeCount = filteredNodes.lazy.filter(model.isNodeIncluded).count
        let eligibleFilteredNodes = filteredNodes.filter(model.isNodeAllowedByName)
        let allFilteredNodesIncluded = !eligibleFilteredNodes.isEmpty
            && eligibleFilteredNodes.allSatisfy(model.isNodeIncluded)

        return Group {
            Section {
                VStack(spacing: 9) {
                    LazyVGrid(columns: filterColumns, spacing: 9) {
                        countryFilter
                        protocolFilter
                    }
                    Button {
                        showsNameFilter = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "text.magnifyingglass")
                                .foregroundStyle(Color.primary)
                                .frame(width: 22)
                            Text("节点名称")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .layoutPriority(1)
                            Spacer(minLength: 8)
                            if let filter = model.nodeExportNameFilter {
                                let draft = NodeNameFilterDraft(pattern: filter.pattern)
                                Text(verbatim: draft.usesRegex ? filter.pattern : draft.keywords.replacingOccurrences(of: "\n", with: " · "))
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .multilineTextAlignment(.trailing)
                            }
                            if model.nodeExportNameFilter == nil {
                                Text("未设置").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("node-name-export-filter")
                }
                .padding(.vertical, 2)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text("筛选")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("取消勾选的节点仍保存在塔台中，但不会写入任何客户端配置。")
                    if let error = model.nodeExportNameFilterError {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }

            Section {
                if filteredNodes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredNodes) { node in
                        nodeRow(node)
                    }
                }
            } header: {
                HStack(spacing: 12) {
                    Text("节点 · \(includedFilteredNodeCount) / \(filteredNodes.count)")
                        // Scope motion to glyphs; a header transaction must not
                        // animate the List's row diff when search is dismissed.
                        .animation(TowerMotion.selection(reduceMotion: reduceMotion)) { content in
                            content.contentTransition(reduceMotion ? .opacity : .numericText(value: Double(includedFilteredNodeCount)))
                        }
                    Spacer()
                    bulkSelectionButton(
                        filteredNodes: eligibleFilteredNodes,
                        allIncluded: allFilteredNodesIncluded
                    )
                }
                .textCase(nil)
            }
        }
        .task(id: resolutionTaskID) {
            await model.resolveIPCountries(for: model.availableNodes)
        }
    }

    private var filteredNodes: [ProxyNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.availableNodes.filter { node in
            guard !query.isEmpty else { return true }
            let presentedNode = model.nodeForPresentation(node)
            return [
                NodeRegionResolver.displayName(for: presentedNode),
                node.server,
                node.kind.title,
                model.subscriptionName(for: node),
            ].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var filterColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 9), count: count)
    }

    private func bulkSelectionButton(
        filteredNodes: [ProxyNode],
        allIncluded: Bool
    ) -> some View {
        Button {
            model.setNodes(filteredNodes, included: !allIncluded)
        } label: {
            Label(
                allIncluded ? String(localized: "全不选") : String(localized: "全选"),
                systemImage: allIncluded ? "xmark.circle.fill" : "checkmark.circle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(filteredNodes.isEmpty)
        .accessibilityIdentifier("toggle-all-filtered-nodes")
    }

    private var countryOptions: [CountryNodeExportGroup] {
        NodeExportGroupBuilder.countryGroups(
            nodes: model.availableNodes,
            countryCode: model.countryCode(for:)
        )
    }

    private var protocolOptions: [ProtocolNodeExportGroup] {
        NodeExportGroupBuilder.protocolGroups(nodes: model.availableNodes)
    }

    private var countryFilter: some View {
        Menu {
            exportGroupSelectionToggle(
                title: String(localized: "全部地区"),
                nodes: model.availableNodes
            )
            Divider()
            ForEach(countryOptions) { option in
                exportGroupSelectionToggle(title: option.title, nodes: option.nodes)
            }
            Divider()
            Button("完成") {}
                .menuActionDismissBehavior(.enabled)
        } label: {
            FilterChip(
                title: String(localized: "国家地区"),
                symbol: "globe.asia.australia",
                isActive: false
            )
        }
        // Region selection is a multi-select task: keep the native menu open
        // for toggles, and dismiss only via Done or a tap outside the menu.
        .menuActionDismissBehavior(.disabled)
        .frame(maxWidth: .infinity)
    }

    private var protocolFilter: some View {
        Menu {
            exportGroupSelectionToggle(
                title: String(localized: "全部协议"),
                nodes: model.availableNodes
            )
            Divider()
            ForEach(protocolOptions) { group in
                let option = group.kind
                exportGroupSelectionToggle(
                    title: option.title,
                    nodes: group.nodes,
                    kind: option
                )
            }
            Divider()
            Button("完成") {}
                .menuActionDismissBehavior(.enabled)
        } label: {
            FilterChip(
                title: String(localized: "协议"),
                kind: nil,
                isActive: false
            )
        }
        // Keep the protocol menu open while selecting multiple kinds.
        .menuActionDismissBehavior(.disabled)
        .frame(maxWidth: .infinity)
    }

    private func exportGroupSelectionToggle(
        title: String,
        nodes: [ProxyNode],
        kind: ProxyKind? = nil
    ) -> some View {
        let eligibleNodes = nodes.filter(model.isNodeAllowedByName)
        let includedCount = eligibleNodes.lazy.filter(model.isNodeIncluded).count
        let selectionState = NodeExportGroupSelectionState(
            includedCount: includedCount,
            totalCount: eligibleNodes.count
        )
        let countSummary = selectionState == .partial
            ? "\(includedCount)/\(eligibleNodes.count)"
            : "\(eligibleNodes.count)"

        return Toggle(
            isOn: Binding(
                get: { selectionState.isMenuSelected },
                set: { shouldInclude in
                    model.setNodes(eligibleNodes, included: shouldInclude)
                }
            )
        ) {
            if let option = kind {
                Label {
                    Text("\(title) · \(countSummary)")
                } icon: {
                    ProtocolMenuIcon(kind: option)
                }
            } else {
                Text("\(title) · \(countSummary)")
            }
        }
        .disabled(eligibleNodes.isEmpty)
    }

    private func nodeRow(_ node: ProxyNode) -> some View {
        let allowedByName = model.isNodeAllowedByName(node)
        let included = model.isNodeIncluded(node)
        let presentedNode = model.nodeForPresentation(node)
        return Button {
            model.setNode(node, included: !included)
        } label: {
            HStack(spacing: 12) {
                ProtocolGlyph(kind: node.kind, size: 18)
                    .foregroundStyle(included ? Color.accentColor : Color.secondary)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(included ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(NodeRegionResolver.displayName(for: presentedNode))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(node.kind.title) · \(model.subscriptionName(for: node))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(!allowedByName ? "名称不匹配" : (included ? "已启用" : "已停用"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(included ? Color.accentColor : Color.secondary)
                SelectionIndicator(isSelected: included)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!allowedByName)
        .accessibilityValue(included ? String(localized: "已启用") : String(localized: "已停用"))
    }

    private var resolutionTaskID: Int {
        model.availableNodes.map { "\($0.id):\($0.server)" }.hashValue
    }
}

/// The same editor used by policy-group name rules, with a separate saved
/// condition that controls which nodes reach every export destination.
struct NodeExportNameFilterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pattern: String
    @State private var previewResult: NodeNameFilterPreviewResult?
    @State private var saveError: String?
    let onSave: (NodeExportNameFilter?) throws -> Void

    init(filter: NodeExportNameFilter?, onSave: @escaping (NodeExportNameFilter?) throws -> Void) {
        _pattern = State(initialValue: filter?.pattern ?? "")
        self.onSave = onSave
    }

    private var previewInput: NodeNameFilterPreviewInput {
        .init(patterns: [pattern], candidates: model.availableNodes.map { [$0.name] }, insensitive: true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NodeNameFilterFields(pattern: $pattern, caseInsensitiveDefault: true, simplified: true)
                } header: {
                    Text("节点名称")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("名称条件会用于所有客户端导出；订阅刷新后新增的节点也会自动匹配。")
                        Text("仅筛选本地节点；代理集合中的节点由客户端获取，不受此处筛选影响。")
                    }
                }
                NodeNameFilterPreview(input: previewInput, result: previewResult,
                    footer: String(localized: "预览基于当前已启用订阅的节点。手动取消勾选的节点仍不会导出。"))
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }
                if model.nodeExportNameFilter != nil {
                    Section {
                        Button("清除名称筛选", role: .destructive) {
                            do {
                                try onSave(nil)
                                dismiss()
                            } catch { saveError = error.localizedDescription }
                        }
                    }
                }
            }
            .navigationTitle("节点名称筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try onSave(NodeExportNameFilter(pattern: pattern, ignoresCase: true))
                            dismiss()
                        } catch { saveError = error.localizedDescription }
                    }
                    .disabled(!pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && (previewResult?.input != previewInput || previewResult?.error != nil))
                }
            }
            .task(id: previewInput) {
                let input = previewInput
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                let result = await input.evaluate()
                guard !Task.isCancelled, input == previewInput else { return }
                previewResult = result
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let symbol: String
    let kind: ProxyKind?
    let isActive: Bool

    init(title: String, symbol: String, isActive: Bool) {
        self.title = title
        self.symbol = symbol
        self.kind = nil
        self.isActive = isActive
    }

    init(title: String, kind: ProxyKind?, isActive: Bool) {
        self.title = title
        self.symbol = "network"
        self.kind = kind
        self.isActive = isActive
    }

    var body: some View {
        HStack(spacing: 7) {
            if let kind {
                ProtocolGlyph(kind: kind)
            } else {
                Image(systemName: symbol)
            }
            Text(title)
        }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .background(
                isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}
