# 待办与待验证

这里只保留未完成事项。已实施的审查修复及测试结果见[审查报告](../plans/2026-09-05-project-audit.md)。

## Tailscale：一次配置，后续方便导入

- 尚未实现；用户要求先记录，等待测试确认。不要与普通节点协议混用，也不要声称所有 Clash / Surge 版本都支持。
- 先确认使用场景：访问 tailnet 节点、MagicDNS、子网路由或出口节点；不同场景所需配置不同。
- 以稳定连接 UUID 维持身份，分别映射支持版本的固定配置段 / 状态目录；不要每次导出重新生成身份。Surge、Mihomo、sing-box 的配置能力和状态复用需分别验证。
- 首阶段确认 Surge / Stash 的实际能力，再评估 Mihomo 与 sing-box；其他客户端保持“不支持/待确认”，不能自动输出社区 fork 私有字段。
- 优先客户端交互登录。一次性授权密钥只用于首次绑定，敏感值使用 Keychain；不保存 OAuth secret，不写进日志、截图、预览或二维码。重新导入是否沿用身份必须实机测试。
- iOS 前台局域网服务不是持久在线服务器。若需要长期稳定订阅地址，需另行确认由哪个用户自有设备托管，不能擅自上传凭据。

研究入口：[Surge](https://manual.nssurge.com/policies/tailscale.html)、[Stash](https://stash.wiki/en/proxy-protocols/proxy-types#tailscale)、[Mihomo](https://wiki.metacubex.one/en/config/proxies/tailscale/)、[sing-box](https://sing-box.sagernet.org/configuration/endpoint/tailscale/)、[Tailscale 身份](https://tailscale.com/docs/concepts/tailscale-identity)、[Auth Key 安全](https://tailscale.com/docs/features/access-control/auth-keys/how-to/secure-auth-keys)、[与其他 VPN 共存](https://tailscale.com/docs/reference/faq/other-vpns)。实施前重新核对支持版本。

## Stash 3.4：兼容性暂缓

2026-09-06 用户确认目前使用 3.4，并反馈当前最新可用版本仍是 3.4；要求先写文档、等待后续版本。维持现有跳过策略，暂不继续修改实现。

- 待用户恢复此项工作或取得新版本后，先核对实际版本和官方能力。Snell v4/v5、Trojan Reality、VLESS XHTTP 的文档门槛为 iOS 3.6+，不能按文档提前假定已可使用。
- 核实 AnyTLS / SOCKS5 / HTTP Reality 是否被 Stash 接受。旧导出确实丢失 Reality 参数，但这不证明客户端不支持；确认支持后补齐参数，逐节点完成导入、握手及实际请求验证。
- 独立核对原生 SS-over-TLS；不要以已支持 SS 的 WebSocket TLS 插件推断支持原生 TLS。
- 恢复支持时覆盖版本差异和所有导出入口，保留明确的跳过提示；不改写源节点，不将 Reality 静默变成普通 TLS。
- 当前跳过节点清单、已通过客户端反馈及测试/安装记录见 [HANDOFF](HANDOFF.md#stash-34暂缓扩展等待后续版本2026-09-06)。

## Loon 剩余节点待定位（暂缓）

- 07 AnyTLS Reality、08 Trojan Reality 补齐参数后已获用户测速成功反馈，生成器修复见 HANDOFF。
- 2026-09-06 用户要求先记文档、转查 Surge，暂停继续试改 Loon。
- Loon 3.5.0：01/02 已经用户名引号对照实测恢复；09、10、11、13 仍失败。13 日志为 QUIC 握手超时且 UDP 收包数为 0，需进一步区分网络/服务端/客户端原因；09 需原始 Reality 参数，不能从其他节点复制公钥。
- 区分漏字段、客户端协议能力和服务端/网络故障。不要仅凭测速失败判定“不支持”并跳过；仅有协议名也不表示完整 TLS / Reality 组合可用。

## Surge 原生 SS TLS 与版本差异（暂记）

- 11 原生 SS TLS 源语义被旧导出丢失；补 `tls=true` / `sni` 后手机仍失败，暂不继续猜字段或替换成 simple-obfs / ShadowTLS。
- 核对明确支持该组合的官方说明或获得运行时握手证据后再决定补齐或跳过。电脑当前是 Mac 6.4.4 (10661)，不能用其检查结果推断更新版本或 iOS 5.21.1 的能力。
- 用户提供的后续版本日志包含 ALPN、ECN、TLS 和 QUIC 修复，没有明确的 SS 原生 TLS 新增声明。若后续在新版电脑验证，先确认版本，隔离测试配置，不影响用户当前代理。
- 13/14 换网络后已恢复；仍需区分网络问题与 ECN 设置的独立影响，不因之前失败过滤 Hysteria2 / TUIC。

## 等待样本或客户端验证

- VMess 名称回退：等用户提供脱敏样本后再改；核对原始返回体、UA 差异及 ps / remarks，不先覆盖服务商原名。
- Surge TLS 失败：需要脱敏错误和对应节点；检查原始 TLS 字段及客户端支持，不以全局关闭证书校验“修复”。
- 订阅 UA 回退 / 兼容格式：确认返回的节点数量和协议没有丢失；配额补请求只读响应头，不能替换原订阅节点正文。
- 同 URL 重复导入：按客户端分别确认覆盖/新增/内部刷新行为。原始订阅嵌入不代表塔台规则和自有节点也会自动更新。
- 代理集合：官方稳定版客户端逐一实测远端格式、策略组动态成员、UA 和下载失败行为；sing-box 社区 provider 示例只能作为研究线索。
- Shadowrocket 的 Salamander 参数、局域网多网卡/路由器场景保留客户端实测，不据生成成功宣称连通。

## 后续评估

- YAML 导出文件命名（2026-09-14 用户建议，待实现）：采用 `塔台-订阅备注-YYYYMMDD-HHmm.yaml`，例如 `塔台-美国节点-20260914-1418.yaml`，便于区分订阅、导出时间及备份恢复；对订阅备注中的文件名非法字符自动做安全处理。实施前明确多订阅合并导出、备注为空及同一分钟重复导出的命名规则，并验证保存与分享后的实际文件名。
- iOS 16 兼容尚未开始，当前最低仍是 iOS 17；需要单独确认收益和替代交互，不降低现有功能质量。
- 用真机 Instruments 测地图和大量节点切换。先收集长 body、hitch、CPU/内存证据，再决定是否后台化生成或进一步拆分视图。
- [开发清单](DEVELOPMENT.md)中的真机触摸、VoiceOver、权限和分享回归不能由单元测试替代。
