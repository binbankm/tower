# 塔台 1.0.18（56）

- 修复部分 IPv6 节点分享链接生成异常，避免分享后无法重新导入。
- 修复 ShadowsocksR（SSR）IPv6 地址解析失败。
- 修复 Shadowsocks（SS）UDP 开关在导入、保存、分享和导出时丢失或被强制开启的问题。
- 修复 Stash 证书指纹字段不兼容导致的 Trojan 等 TLS 节点连接失败。

更新后请先刷新订阅，再重新导出配置，以恢复旧数据中可能丢失的参数。

## 验证边界

Stash 修复已获用户真机确认。Clash / Clash Mi 的 IPv6 连接反馈仍在排查；Clash Mi 的核心 IPv6 设置可能覆盖订阅配置，本版不宣称已解决所有客户端的 IPv6 连通性问题。SS UDP 指普通 UDP 转发，本次不新增 UDP-over-TCP 支持。

此发布提供源码。TestFlight 由开发者后续自行处理，未附新的 Mac 安装包。
