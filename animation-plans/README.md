# 动画与交互改进计划

## 2026-09-27 审查（基线 `5672973` 加工作区未提交改动）

范围：全部界面的动画、交互流程、相关算法和结构。依据是 improve-animations 的八类标准，另外按用户要求覆盖流程、算法和结构。这次审查只读源码，没有修改应用代码，也没有构建、安装或提交。

[2026-09-11 审查](2026-09-11-motion-audit.md)提出的 13 项已全部落地，本次不重复。以下都是新发现，或者是 1.0.16–1.0.21 以及当前工作区引入的问题。

### 已核实的问题（按投入产出比排序）

| # | 严重度 | 类别 | 位置 | 问题 | 修复要点 | 计划 |
|---|---|---|---|---|---|---|
| 1 | HIGH | 算法 | `Tower/AppModel.swift:258-296`（工作区） | 名称导出筛选在主线程同步跑正则，墙钟预算 1 秒。每次勾选节点都会让整份缓存失效并重跑；主线程繁忙时可能超时，导致所有导出变成 0 节点，导出页却不说明原因 | 名称匹配单独缓存，勾选时命中缓存；导出页显示筛选错误 | [001](001-name-filter-cache-and-visibility.md) |
| 2 | MEDIUM | 流程 | `Tower/Features/Rules/RulesView.swift:392, 422, 664` | 点卡片进入的是“定制”，选中只在角落。定制未选中的方案不会提示，改完导出的仍是旧方案，用户会以为修改没生效 | 定制弹窗顶部显示当前导出方案，并提供“改用此方案” | [002](002-customize-unselected-scheme.md) |
| 3 | MEDIUM | 漏掉的动画 / 布局 | `Tower/Features/Subscriptions/NodeMapOverview.swift:711-745` | 延迟徽标在菊花、结果和不可达之间宽度不同，也没有过渡。批量测速时每行名称的截断位置逐个跳动，结果文字直接出现 | 最小宽度 56pt 固定槽位，局部淡入，毫秒数用数字过渡 | [003](003-latency-badge-stable-slot.md) |
| 4 | MEDIUM | 目的 / 流程 | `Tower/Features/Subscriptions/AddSourceSheet.swift:728, 770` | 打开面板时先聚焦弹出键盘，剪贴板填充成功后又收起。最常见的路径上出现一次无意义的键盘升降 | 等剪贴板结果出来再决定是否聚焦 | [004](004-add-sheet-deferred-focus.md) |
| 5 | MEDIUM | 性能 | `AddSourceSheet.swift:70` | `detectedKind` 是计算属性，每次渲染至少调用 2 次；批量粘贴多行时，每次都在主线程完整解析全部节点 | 缓存成 `@State`，大文本放后台 | [005](005-cache-source-detection.md) |
| 6 | MEDIUM | 结构 / 性能（需真机确认） | `Tower/Design/TowerTheme.swift:424-460` | `CardSwipeDeletion` 会把内容渲染两次（一份隐藏副本加一份原生 `List` 副本），而且每张卡片各带一个 `List`。副本里的 `.task`、`sensoryFeedback` 也会存在两份；自有节点很多时，滚动首页等于滚动几十个集合视图 | 先用 Instruments 在真机测几十张自有节点卡片的滚动表现；确实有问题时，再考虑改成只测高度的轻量副本，或用一个共享 `List` 承载滑动删除 | 未写计划：需要先取证 |
| 7 | LOW | 一致性 / token | `TowerApp.swift:71, 217, 267, 277-280`；`SubscriptionsView.swift:155, 244`；`ImportRuleSchemeSheet.swift:200`；`SettingsView.swift:945`；`TowerTheme.swift:207` | 浮层和卡片的入场参数各写各的：弹簧响应有 0.3、0.34、0.35、0.36、0.4 五种，入场缩放有 0.92 和 0.96 两种，减弱动态模式下混用 easeInOut 和 easeOut；刷新失败报告只做淡入，与相邻的任务卡片不一致 | 在 `TowerMotion` 新增 `surface(reduceMotion:)`（`.spring(response: 0.34, dampingFraction: 1)` / 减弱动态时 `.easeOut(0.14)`）和 `surfaceEntryScale = 0.96`，统一替换。`MotionDesignTests` 里的 0.92 是选中符号的缩放，不要一起改 | 可按需补写计划 |
| 8 | LOW | 算法 | `SubscriptionsView.swift:757` | 订阅卡片的 `contextMenu` 每次渲染都调用 `model.nodes(for: source).isEmpty`，对全部节点做一次过滤。这正是第 773 行注释里说要避免的开销 | 改为 `model.nodeCount(for: source) == 0`，两者的过滤条件一致 | 小改，不单独写计划 |
| 9 | LOW | 流程一致性 | `NodeMapOverview.swift:337-406` 与 `:408` | 订阅展开列表和地图地区列表里的节点行（`CompactNodeRow`）点了没有反应，详情只能长按打开；自有节点行（`ExpandableNodeRow`）则是轻点展开。同样外观的节点行，交互方式却不同 | 让 `CompactNodeRow` 轻点也打开“节点详情”弹窗（它已经存在），长按菜单保留 | 待产品确认 |
| 10 | LOW | 死代码 | `SubscriptionsView.swift:15, 20, 214-220`；`NodeMapOverview.swift:664` | `ScrollViewReader { _ in }` 从未使用 proxy；`SubscriptionScrollTarget.top` 的注释说“刷新完成后回到这里”，但没有任何代码滚动过去；`NodeRegionDetailLine` 没有被引用 | 删除。注意 `SubscriptionInteractionTests.swift:1169-1171` 用源码字符串锁定了 `displayedSubscriptions`，删之前要同步修改这个测试 | 小改 |

### 漏掉的动画机会（新增项，不是纠错）

- **地图选中地区后，节点列表可能在屏幕外**：列表出现在地图下方，小屏手机上看不到，用户会觉得“点了没反应”。可以在列表标题不在可见区域时，用 `TowerMotion.disclosure` 把标题滚到可见位置，但不要把地图整体推出屏幕。页面上已经有 `SubscriptionScrollTarget.nodes` 这个锚点；proxy 目前没接上（见第 10 项）。是否滚动、滚多少需要真机试手感再定。
- **测速按钮完成时的收尾**：胶囊按钮从“n/n · 停止”回到“测速”时只做了宽度过渡。可以在完成的一刻加一次 `.sensoryFeedback(.success, …)`。这个动作不频繁，值得给一点完成反馈。

### 遵循既有决定，不作为问题报告

- 手动刷新（包括单个订阅的刷新按钮）使用居中遮罩和进度卡片，这是 2026-09-11 按用户要求做的统一设计（见 HANDOFF 第 420-459 行）；自动刷新不使用遮罩。
- 地图松手只保留很小的惯性（`momentumFactor = 0.04`），源码注释明确是为了防止甩一下就划过好几个国家。
- 导出页状态头在切换客户端时显示上一个结果、不做动画，这是为了避免“就绪、忙碌、就绪”的闪烁（`ExportView.swift:31-35` 的注释）。
- 规则页“点卡片进入定制、角落选中”的点击分区本身不改，第 2 项只补提示。
- 标签栏切换时的触感有调试开关，属于有意保留。

### 结构观察（不写计划）

- `TowerTests` 里大约有 118 处直接读取 Swift 源码、断言字符串的“源码守卫”，集中在 `RepositoryConsistencyTests` 和 `SubscriptionInteractionTests`。它们能防止回退，但会把实现细节锁死：一次无害的重命名或清理就会让测试变红。建议新增约束时优先写行为测试（模型层或 UI 测试），源码守卫只用于 `CLAUDE.md` 里那些不可破坏的约束。
- `AppModel.swift`（3967 行）、`ConfigurationGenerator.swift`（4866 行）和 `RulesView.swift`（2595 行）仍然是单文件大类型。之前的审查已经决定不因为行数整体重写，这里维持这个判断；以后新增功能时，优先把相应职责提取成独立类型（参考已抽出的 `SourceUpdateCoordinator`、`ConfigurationCache`）。

## 计划与执行顺序

| 计划 | 标题 | 严重度 | 状态 | 依赖 |
|---|---|---|---|---|
| [001](001-name-filter-cache-and-visibility.md) | 名称导出筛选缓存与错误可见性 | HIGH | DONE | 需要工作区的名称筛选功能已存在；应在该功能提交前后尽快处理 |
| [002](002-customize-unselected-scheme.md) | 定制未选中方案的提示与切换 | MEDIUM | DONE | 无 |
| [003](003-latency-badge-stable-slot.md) | 延迟徽标固定占位与局部过渡 | MEDIUM | DONE | 无 |
| [004](004-add-sheet-deferred-focus.md) | 添加面板延后聚焦 | MEDIUM | DONE | 与 005 修改同一文件，建议先 004 后 005，分两次提交 |
| [005](005-cache-source-detection.md) | 输入识别结果缓存 | MEDIUM | DONE | 在 004 之后 |

建议顺序：001 → 002 → 003 → 004 → 005。001、002 新增界面文案，需要补齐 15 种语言；003、004 需要真机验收。

### 实施结果（2026-09-27）

五项计划已全部实施，基线为检查点提交 `bac4ff9`：

- 001：名称匹配使用独立缓存，按「筛选条件 + 可用节点 id/名称」判断是否命中，勾选节点不再重新跑正则；新增 `nodeNameFilterEvaluationCount` 计数和回归测试。导出页在筛选失败时显示橙色原因（`export-name-filter-error`）。超时语义和“失败时不放行”保持不变。
- 002：规则定制页在未选中的方案顶部说明当前导出所用方案，并提供“改用此方案”（`customization-use-scheme`）。不会自动切换。
- 003：延迟徽标有内容时占用至少 56pt 的固定槽位。槽位宽度写在动画作用域之外，行布局不插值；徽标内部的状态切换局部淡变，毫秒数变化用数字过渡，减弱动态时只淡变。
- 004：添加面板等剪贴板读取结果出来后再决定焦点。填充成功时键盘不出现；读取为空、不受支持或失败时，只有用户还没有自己选中输入框，才把焦点放进输入框。
- 005：`detectedKind` 改为 `@State`，只在 `sourceValue` 变化时计算，超过 4 KB 的文本在后台识别；识别结果与当前输入不一致时，“添加”按钮保持禁用。

新增 3 条文案，15 种语言为人工翻译，术语沿用目录中已有的译法（例如“规则方案”译为 Rule profile）。

验证（正式版 Xcode 27.1，iPhone 17 模拟器）：TowerTests 1178 项 XCTest（5 项跳过、0 失败）与 100 项 Swift Testing 全部通过；`check_localization.sh` 提取 1034 条，全部通过。模拟器测试不能替代真机验收：003 的批量测速观感、004 的剪贴板与键盘表现，都需要按各计划的 Feel check 在真机确认。

### 第二轮实施结果（2026-09-27，表中第 6–10 项及两个新增动画）

- 第 6 项（`CardSwipeDeletion`）：先测量再决定。新增仅 Debug 生效的 `--disable-card-swipe` 对照开关，以及 `testPerformanceAuditLocalNodesWithCardSwipe` / `WithoutCardSwipe` 两条滚动测试（1,000 节点测试数据，其中 40 个自有节点，数据存在隔离的临时文件里）。iPhone 17 模拟器对照：滚动自有节点区域时，CPU 指令数平均 2,458 万 kI 对 1,437 万 kI，带滑动删除约多 70%，几乎都来自每张卡片各自的 `List`。试过“量到行高后去掉隐藏副本”，只省约 3%，而且卡片高度变化时会晚一帧，所以没有保留。自定义横向拖动手势之前试过、又因展开内容跟着横移而移除（见 HANDOFF），所以保留原生滑动删除，等真机数据再决定是否重写。真机测量这次没做成：测试运行器被拒绝连接，需要在 iPhone 的「设置 → 开发者」里打开「启用 UI 自动化」后重试。已确定的问题已修复：新增环境值 `isSwipeSizingCopy`，隐藏副本不再重复触发勾选触感和 IP 国家查询。
- 第 7 项：`TowerMotion` 新增 `surface(reduceMotion:)`（弹簧响应 0.34、无回弹；减弱动态时 0.14 秒 easeOut）和 `surfaceTransition(reduceMotion:)`（缩放到 0.96 并淡入淡出）。Toast、刷新进度卡、导入任务卡、Mac 引导浮层、局域网二维码、欢迎页收起都已改用它们。刷新失败报告把遮罩和卡片拆开：遮罩只淡变，卡片与其他浮层一致；关闭入口仍只有一个。Mac 地图展开改用 `disclosure`。欢迎页退出时放大到 1.04 的过渡保留不变。
- 第 8 项：订阅卡片长按菜单改用缓存的节点数 `metrics.nodeCount`。
- 第 9 项：`CompactNodeRow` 的图标、名称和延迟区域点一下就打开“节点详情”，按下时有透明度反馈，并加了无障碍提示“轻点查看节点详情”；分享按钮和长按菜单不变。
- 第 10 项：删除 `SubscriptionScrollTarget.top` 锚点、`NodeRegionDetailLine`，以及首页两个直通属性 `displayedSubscriptions` / `displayedLocalNodes`（源码守卫测试改为检查 `ForEach(model.subscriptions)`，意图不变）。`ScrollViewReader` 保留，改用于下面的地区滚动。
- 新增：在地图上选中国家后，如果它的节点列表标题和前几行不在屏幕内，就以最小幅度滚进视野（`SubscriptionScrollTarget.selectedRegionNodes`）；已经可见时不滚动；减弱动态时直接跳到位置，不做滚动动画。
- 新增：由地图“测速”按钮发起的整批测速完成时，给一次成功触感；中途停止或其他地方的单节点重测不触发。

验证：TowerTests 1178 项 XCTest（5 项跳过、0 失败）与 100 项 Swift Testing 全部通过；本地化检查 1035/1035。界面交互测试按用户要求提前停止（已完成 25 项，其中 22 项通过）。三项失败单独重跑：`testManualDoneDismissesKeyboard`、`testFilterAtAccessibilityTextSize` 重跑通过，是偶发失败；`testPersistentExportNameFilter` 在修复前的提交 `bac4ff9` 上同样失败，原因是测试在等一句界面已不再显示的“筛选持续生效”，属于既有的过期断言，已单独列为后续任务。
