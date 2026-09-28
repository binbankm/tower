# Tailscale 内网：各客户端写法与塔台的实现

更新：2026-09-28。本文依据各客户端官方文档，并用自建 Headscale 在手机和本机内核上实测；版本号以文中注明的为准，发布前应重新核对。

## 它解决什么问题

代理客户端（Surge、Stash 等）开着时，手机上不能同时再开 Tailscale App：iOS 同一时间只允许一个 VPN。这几个客户端把 Tailscale 做成了一种**出站策略**：客户端自己加入 tailnet，成为其中一台设备，只把你用规则指定的流量（家里电脑的 Tailscale 地址、MagicDNS 名字、家里子网）送进 tailnet，其他流量照常走代理或直连。

要点：

- 它**不是代理节点**。目的地不在 tailnet 里时直接失败，不会回退直连，所以不能放进「节点选择」「自动选择」之类的策略组，只能靠规则把特定流量送过去。
- 每个客户端都会在 tailnet 里注册成**一台独立设备**（Surge 一台、Stash 一台……）。它们只负责访问别人，不会把手机发布成子网路由或出口节点，也不接受 tailnet 里的入站连接。
- 能访问什么，最终由 Tailscale 控制台决定：ACL、子网路由是否已批准、MagicDNS 是否开启。

## 在塔台里怎么用

1. 设置 → 节点与配置 → Tailscale 内网 → 添加。**不需要**再添加任何「Tailscale 节点」。
2. 字段：
   - **名称**：导出后在客户端里显示的策略名。
   - **控制服务器**：留空为官方 Tailscale；自建 Headscale 填它的 HTTPS 地址。
   - **Auth Key**（可选）：留空则在 Surge / Stash 里交互登录；Clash / mihomo 和 sing-box MT 实际上需要它。只存本机钥匙串，不同步 iCloud，但会写进导出的配置。
   - **家里子网**（可选）：例如 `192.168.1.0/24`。家里必须有一台设备在 Tailscale 里发布这个子网，并在控制台批准。
   - **MagicDNS 后缀**（可选）：Tailscale 控制台 DNS 页面上的 `tailXXXX.ts.net`。Surge 5.21+ / Stash 3.6+ 可以自己发现；mihomo 和 sing-box 需要它才能按设备名访问。
   - **设备名**：默认 `tower`，每个客户端再加后缀，例如 `tower-surge`、`tower-stash`。
3. 导出时选「完整配置」。「仅节点」模式不写 Tailscale。导出后可在「配置预览」里确认（Auth Key 在预览中打码）。

## 各客户端

### Surge（iOS 5.20+ / Mac 6.7+）

官方文档：<https://manual.nssurge.com/policies/tailscale.html>

写法由两部分组成：`[Proxy]` 里的一行策略，加一个同名的 `[Tailscale <section-name>]` 段。

```ini
[Proxy]
家里 = tailscale, section-name=tower-tailnet-1a2b3c4d

[Tailscale tower-tailnet-1a2b3c4d]
interactive-login = true      # 或 auth-key = tskey-auth-…，两者只能有一个
control-url = https://…       # 可选，默认官方
hostname = tower-surge        # 可选
```

- **登录**：`auth-key` 与 `interactive-login` 二选一。交互登录需要 **iOS 5.21 / Mac 6.8** 以上：在 Surge 里编辑这个策略，从策略编辑页发起登录，在浏览器里授权。`interactive-login = true` 这一行只是「引用本机登录状态」，不含凭据；换设备或本机状态丢失时要重新登录。
- **身份保持**：交互登录的状态按**配置段名**保存；Auth Key 登录的状态按 **Key 的哈希**保存。改段名或换 Key 都会变成新设备。
- **自动路由**（5.21+ 默认开启，`auto-add-magic-dns-rule`）：会话建立后自动把 MagicDNS 后缀和每个对端的 Tailscale 地址路由到这个策略。**子网路由和出口节点不会自动路由**，需要显式规则。
- 其他字段：`exit-node`（`none` / `auto` / 指定设备）、`derp-only`、`idle-keepalive`（5.21+，默认常驻）、`prefer-ipv6`、`dns-server`、`mtu`；策略行上可加 `underlying-proxy`（让 DERP 走另一个策略，此时只走中继）、`test-url`（只接受 http://）、`test-timeout`。
- 注意：控制服务器地址按普通规则出站，**不能让它匹配到这个 Tailscale 策略本身**，否则会死锁。
- 没有出口节点时，Surge 的测速用 Tailscale 自己的连通探测；配置了公网 `test-url` 反而会失败。

### Stash（iOS / tvOS 3.4+，macOS 4.2+）

官方文档：<https://stash.wiki/en/proxy-protocols/proxy-types#tailscale>

```yaml
proxies:
  - name: 家里
    type: tailscale
    auth-key: tskey-auth-…         # 可选
    hostname: tower-stash          # 可选
    control-url: https://…         # 可选
    # exit-node: …                 # 可选
    # auto-route-disabled: false   # 可选
```

- **登录**：填 `auth-key` 自动完成；不填时，在 Stash 的代理列表里打开这个节点的菜单，进入 Tailscale 页面，点「开始认证」。认证过一次后通常不需要再填 Key。
- **换控制服务器**会使用另一份身份，需要重新认证。
- **自动路由**需要 **iOS 3.6+ / macOS 4.3+**：自动把 MagicDNS 后缀和对端地址交给这个节点，且排在配置规则之前。**3.4 / 3.5 没有自动路由**，必须写规则。
- `exit-node` 不写时会自动从可用出口节点里选一个；在 Tailscale 页面里手动选择的会覆盖配置。

### Clash / mihomo 系（mihomo 内核 1.19.25+）

官方文档：<https://wiki.metacubex.one/en/config/proxies/tailscale/>

适用：Clash Mi、Clash Verge Rev、FlClash、Mihomo Party、ClashMac 等，前提是内置 mihomo ≥ 1.19.25 且带 `with_gvisor` 构建标签（官方发布版带）。

```yaml
proxies:
  - name: 家里
    type: tailscale
    auth-key: tskey-auth-…       # 可选；不填则登录链接只打印在日志里
    control-url: https://…       # 可选
    hostname: tower-clash-mi
    state-dir: tower-tailnet-1a2b3c4d   # 身份保存位置，默认 tailscale
    udp: true
    accept-routes: true          # 要访问家里子网必须打开
    # exit-node: 100.64.0.1 / auto:any
```

- **没有自动路由**：必须写规则。目的地不在 Tailscale 路由里时直接失败，不回退直连。
- **懒启动**：第一条匹配的连接才会启动 Tailscale，所以第一次访问超时是正常的，重试即可。
- **没有交互登录界面**：不填 Key 时登录链接只出现在日志里，实际使用建议填 Auth Key。

### sing-box（1.12+）

官方文档：<https://sing-box.sagernet.org/configuration/endpoint/tailscale/>、<https://sing-box.sagernet.org/configuration/dns/server/tailscale/>

Tailscale 在 sing-box 里是 **endpoint**，不是 outbound；MagicDNS 需要单独的 `tailscale` DNS 服务器。

```json
{
  "endpoints": [{
    "type": "tailscale", "tag": "家里",
    "state_directory": "tower-tailnet-1a2b3c4d",
    "auth_key": "tskey-auth-…", "control_url": "https://…",
    "hostname": "tower-sing-box", "accept_routes": true
  }],
  "dns": {
    "servers": [{ "type": "tailscale", "tag": "家里 DNS", "endpoint": "家里" }],
    "rules": [{ "action": "route", "domain_suffix": ["tailXXXX.ts.net"], "server": "家里 DNS" }]
  },
  "route": {
    "rules": [{ "action": "route", "domain_suffix": ["tailXXXX.ts.net"],
                "ip_cidr": ["100.64.0.0/10", "fd7a:115c:a1e0::/48", "192.168.1.0/24"],
                "outbound": "家里" }]
  }
}
```

- **没有自动路由**，也没有交互登录界面（登录链接在日志里）。
- 不填 MagicDNS 后缀时，只能用 Tailscale IP 访问。

### 不支持的客户端

| 客户端 | 情况 |
| --- | --- |
| Shadowrocket | 2.2.92 更新说明提到 Tailscale，但没有公开配置字段。实测 Clash YAML 的 `type: tailscale` 和 Surge 写法都没有向控制服务器注册。 |
| Loon、Quantumult X、Egern | 官方文档里没有 Tailscale 类型。 |
| Hiddify、Karing | 基于 sing-box，但应用本身还没有导入 Tailscale endpoint（Karing 源码中仍是 todo）。 |
| V2Box、Anywhere | 只有节点订阅，不涉及。 |

塔台对这些客户端跳过 Tailscale，并在导出页「兼容性提示」里说明。

## 塔台导出的规则

每个启用的 Tailscale 内网，塔台都会在**所有规则之前**插入：

| 规则 | 作用 |
| --- | --- |
| `DOMAIN-SUFFIX,<MagicDNS 后缀>` | 按设备名访问（填了后缀才写） |
| `IP-CIDR,100.64.0.0/10` | Tailscale IPv4 地址段 |
| `IP-CIDR6,fd7a:115c:a1e0::/48` | Tailscale IPv6 地址段 |
| `IP-CIDR,<家里子网>` | 家里局域网（经子网路由器） |

策略本身不加入任何策略组。Surge 5.21+ / Stash 3.6+ 自带自动路由，这些规则与之重复但无害；Stash 3.4、mihomo、sing-box 必须靠它们。

## 已知问题与待确认

1. **塔台自己导出的配置还没在手机上逐个验证过。** 手机实测（Surge、Stash 3.4、Clash Mi、sing-box MT 全部通过）用的是手写的测试配置；塔台的实际导出只在本机 mihomo 和 sing-box 内核上连通过。Surge 和 Stash 的塔台导出需要再上手机确认。
2. **没填 Auth Key 时，Surge 必须是 iOS 5.21 / Mac 6.8 以上。** 更早的版本不认识 `interactive-login`，等于没有配置登录方式，注册会失败；只能改用 Auth Key。
3. **`100.64.0.0/10` 规则范围很大。** 它会把所有该网段的目的地都送进 tailnet，包括不属于你 tailnet 的地址（这个网段也是运营商级 NAT 的共享地址段）。实际很少有公网服务用它，但确实比 Surge / Stash 自动路由的「只路由已知对端」宽。
4. **家里子网规则在家时也生效**：手机连着家里 Wi-Fi 时，访问 `192.168.1.x` 也会绕 tailnet 走一圈。Tailscale 会尽量直连，通常仍能用，但比直接访问局域网慢。
5. 导出页把「没有 Auth Key，请在客户端登录」放在「兼容性提示」里，看起来像错误，其实是正常提示。

## 验证方法

1. 导出后在「配置预览」里确认：Surge 有 `= tailscale, section-name=` 行和末尾的 `[Tailscale …]` 段；Clash / Stash 的 `proxies:` 第一项是 `type: tailscale`；`rules:` 前几条是上表的规则。
2. 在客户端完成登录（或填 Key），在 Tailscale 控制台确认出现 `tower-surge` 之类的新设备。
3. 切到蜂窝网络，分别打开：家里电脑的 Tailscale IP、它的 MagicDNS 名字、家里子网里的某个地址（需已发布并批准子网路由）。
4. 重新导入同一份配置后，控制台里不应多出新设备。
