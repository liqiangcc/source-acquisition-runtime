# 网络边界

## 1. 为什么必须拆成两条链路

本项目同时存在两类“隧道/代理”问题，但它们解决的是完全不同的方向。

### 入站：AI 如何访问 MCP

```text
ChatGPT Web
↓
Remote MCP / Secure MCP Tunnel
↓
MCP Gateway
↓
Chrome DevTools MCP
```

### 出站：Chrome 如何访问互联网

```text
Chrome
↓
Direct / Proxy / TUN
↓
Internet
```

两者不能共用一个模糊的 `tunnel` 配置概念。

## 2. 端口与暴露矩阵

| 组件 | 示例监听 | 谁可以访问 | 是否远程暴露 |
| --- | --- | --- | --- |
| Chrome CDP | `127.0.0.1:9222` | runtime 本机 | 否 |
| MCP Gateway | `127.0.0.1:<port>` 或受控本地 socket | Tunnel client / 本机 | 默认否 |
| Secure MCP Tunnel client | 出站连接 | OpenAI Tunnel 服务 | 不要求本机入站公网端口 |
| noVNC / remote desktop | 可配置 | 人工管理员 | 仅受控接入 |
| Proxy/TUN | 主机本地 | Chrome/host | 不作为 MCP 入口 |

核心规则：

> 不通过 Cloudflare Tunnel、OpenAI Secure MCP Tunnel、端口映射或公网反向代理直接暴露 Chrome CDP。

Remote MCP 的外部入口只能到 MCP transport 层。

## 3. Chrome CDP

Chrome DevTools MCP 官方当前支持：

```text
--browser-url=http://127.0.0.1:9222
```

Chrome remote debugging 具有浏览器控制能力，所以架构上把它视为本机高权限接口。

要求：

- 监听 localhost；
- 使用独立 Browser Profile；
- 不把端口加入公网安全组；
- 不把它作为 Tunnel origin；
- 不让其他不相关服务共享这个 profile 的 CDP。

## 4. Remote MCP

OpenAI 当前文档说明：ChatGPT 不直接连接本机 MCP；MCP 在私网、on-prem 或开发机器上时，可以通过 Secure MCP Tunnel 连接到支持的 OpenAI 产品。

因此推荐拓扑：

```text
ChatGPT
   │
   ▼
OpenAI control plane
   │
   ▼
Secure MCP Tunnel
   │
   ▼
localhost MCP Gateway
   │
   ▼
Chrome DevTools MCP
```

这里 Tunnel 的终点是 MCP Gateway，而不是 Chrome。

Secure MCP Tunnel 的具体可用性、工作区权限和配置流程属于产品能力，部署脚本不能假定所有 ChatGPT 账户都具有相同 entitlement。`doctor` 应把“本地 MCP 正常”和“ChatGPT/Tunnel entitlement 正常”分成两个检查结果。

## 5. 公网 HTTPS 作为可替换入口

架构允许未来存在：

```text
ChatGPT
↓
Authenticated HTTPS Remote MCP
↓
MCP Gateway
```

但这只是 Remote Access Layer 的另一种实现。

无论采用哪种实现：

```text
外部世界
    ↓
Remote MCP boundary
    ↓
MCP Gateway
```

这一分离点不变。

## 6. Chrome 出站 Direct / Proxy / TUN

### Direct

服务器网络本身满足访问条件时：

```text
Chrome → Internet
```

这是最简单基线，Pilot 应优先确认能否使用。

### HTTP/SOCKS Proxy

```text
Chrome
↓
localhost/system proxy
↓
upstream
↓
Internet
```

如果只有 Chrome 需要代理，优先浏览器级或进程级配置，减少对 MCP/Tunnel 的影响。

### Host TUN

```text
Chrome
↓
Linux routing
↓
TUN interface
↓
upstream
```

适用于需要由主机透明接管出站流量的环境。

这里的 TUN 与 Remote MCP Tunnel 没有协议或职责上的直接关系。

## 7. 避免代理回环

如果服务器启用了全局 TUN/透明代理，要明确排除本机控制流量，至少关注：

```text
127.0.0.0/8
localhost
MCP Gateway local endpoint
Chrome CDP local endpoint
必要的管理网段
```

否则可能出现：

```text
Chrome DevTools MCP
→ 127.0.0.1:9222
→ 被 TUN 错误接管
→ 连接异常
```

或者 Tunnel client 自身流量被错误链式代理，导致难以诊断的循环和超时。

具体 bypass 列表由部署实现根据所选 TUN/Proxy 软件生成。

## 8. 故障分类

网络诊断必须报告故障所在层，而不是统一返回“网页打不开”。

建议分类：

```text
chrome-process-down
cdp-unreachable
mcp-process-down
mcp-tool-error
gateway-unreachable
tunnel-disconnected
remote-client-unavailable
outbound-dns-failure
outbound-connectivity-failure
site-session-expired
site-page-error
```

例如：

```text
ChatGPT 看不到 MCP
```

不应该第一反应去重启 Chrome；先检查 Remote MCP/Tunnel。

而：

```text
MCP 能调用，但小红书打不开
```

应检查 Chrome 出站网络、DNS、站点 Session 和页面状态。

## 9. 网络健康检查

`doctor` 最终至少输出：

```text
[PASS] chrome process
[PASS] cdp localhost
[PASS] chrome outbound dns
[PASS] chrome outbound https
[PASS] chrome-devtools-mcp
[PASS] mcp gateway
[PASS] tunnel client
[PASS] remote tool discovery
[WARN] xhs session requires manual login
```

每项独立，不能只返回一个总布尔值。

## 10. 当前不变量

```text
CDP 永远不是远程 API
Remote MCP 与 Chrome 出站网络独立
Tunnel 不直接终止在 Chrome
Browser Profile 不因网络实现变化而变化
Skill 不依赖某一个具体代理供应商
```

这些规则应比具体 Tunnel/TUN 产品活得更久。