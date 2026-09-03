# linux-primary-01 MCP Gateway Pilot

## 1. 目标

在不改变 Chrome CDP 本机安全边界的前提下，将现有 stdio Chrome DevTools MCP 适配为 localhost Streamable HTTP MCP endpoint，为后续 Secure MCP Tunnel 提供 origin。

目标拓扑：

```text
Remote MCP / Tunnel
        ↓
127.0.0.1:8765 MCP Gateway
        ↓
Chrome DevTools MCP stdio
        ↓
127.0.0.1:9222 CDP
        ↓
persistent Chrome
```

CDP 不作为远程 API。

## 2. 候选评估

### supergateway 3.4.3

已确认支持 stdio → Streamable HTTP，但当前实现的 Streamable HTTP server 使用 `app.listen(port)`，没有可配置 host bind。由于本 Pilot 要求 Gateway 默认不监听非 loopback 地址，因此不采用。

### Python mcp-proxy 0.12.0

能力满足 localhost bind，但目标机 Python/PyPI 依赖链增加了额外部署复杂度。验证期间还发现系统原 pip mirror TLS 失败；虽然切换到官方 PyPI 后可以继续安装，但最终不采用此实现。

### TBXark/mcp-proxy 0.58.0

采用单 Linux amd64 release binary。

固定信息：

```text
version: 0.58.0
release artifact: mcp-proxy_0.58.0_linux_amd64.tar.gz
sha256: fdaea13fe9af4119349628a1e62ef9e67338c96b9939c2818cf2a9ace26121dd
```

该 SHA256 已在 `linux-primary-01` 实机下载后与 GitHub release digest 对比，结果 PASS。

## 3. 已完成的临时实机验证

使用临时配置：

```json
{
  "mcpProxy": {
    "baseURL": "http://127.0.0.1:8765",
    "addr": "127.0.0.1:8765",
    "type": "streamable-http"
  }
}
```

实际结果：

```text
mcp-proxy version: 0.58.0
listener: 127.0.0.1:8765
100.109.226.71:8765: not reachable
Chrome CDP: remains 127.0.0.1:9222
```

Gateway 成功启动 Chrome DevTools MCP downstream，并在日志中证明：

```text
Successfully initialized MCP client
Successfully listed tools
count=29
Connected client=chrome-devtools
route=/chrome-devtools/
```

因此以下部分已经证明：

```text
Gateway process can bind loopback only: PASS
Gateway can initialize Chrome DevTools MCP downstream: PASS
Gateway can enumerate downstream tools: PASS (29)
CDP remains localhost-only: PASS
```

## 4. 尚未声明 PASS 的部分

在继续执行 Streamable HTTP 外部客户端 smoke 和 systemd 固化回归时，`agent-runtime-mcp` 的 tmux backend 返回：

```text
BACKEND_UNAVAILABLE
```

因此以下项目必须等目标执行通道恢复后真实验证，不能由临时结果推断：

```text
HTTP client initialize through /chrome-devtools/mcp: pending
HTTP client tools/list + list_pages: pending
source-mcp-gateway.service install/restart: pending
doctor --gateway: pending
```

failure class：

```text
control-plane-runtime-unavailable
```

这不是 Gateway 或 Chrome DevTools MCP failure。

## 5. 仓库固化

本 Pilot 固化：

```text
deploy/gateway/version.env
deploy/gateway/gateway.json
deploy/gateway/install.sh
deploy/gateway/source-mcp-gateway.service
scripts/gateway-smoke.mjs
```

Gateway endpoint：

```text
http://127.0.0.1:8765/chrome-devtools/mcp
```

health endpoints：

```text
http://127.0.0.1:8765/_healthz
http://127.0.0.1:8765/_readyz
```

## 6. 下一 Gate

只有 HTTP client smoke + systemd restart regression 全部通过后才将 MCP Gateway Gate 标为 PASS，然后进入 Secure MCP Tunnel / Remote MCP Gate。
