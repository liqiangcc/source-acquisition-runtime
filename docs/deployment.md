# 服务端部署

## 1. 部署目标

目标不是“把 Chrome 装上去”，而是从一台干净 Linux 服务器得到一个可重复验证的运行栈：

```text
Linux host
├── Chrome
├── dedicated browser profile
├── optional virtual display / remote desktop
├── Chrome DevTools MCP
├── MCP transport gateway
├── Remote MCP tunnel client
├── optional outbound proxy/TUN
└── health checks
```

第一阶段以单机、单用户、单浏览器 profile 为主，不先做集群化。

## 2. 推荐环境

首个受支持目标：

- Ubuntu / Debian 类 Linux；
- x86_64 优先完成 Pilot；
- systemd 管理长期运行进程；
- Node.js 版本满足当前 Chrome DevTools MCP 要求；
- Google Chrome Stable；
- 有持久磁盘保存浏览器 profile 和 Source Artifact。

ARM64、多发行版、容器化部署在主链路通过后再增加。

## 3. 运行用户与目录

推荐创建独立运行用户，例如：

```text
source-runtime
```

建议目录：

```text
/opt/source-acquisition-runtime/     # 程序与部署文件
/etc/source-acquisition-runtime/     # 非秘密配置
/var/lib/source-acquisition-runtime/
├── chrome-profile/                  # 持久浏览器 profile
├── artifacts/                       # Source Artifact
└── state/                           # runtime state
/var/log/source-acquisition-runtime/ # 日志
```

Browser Profile、Cookie 和站点 Session 不进入 Git。

## 4. Chrome 部署模式

### 推荐：长期运行 Chrome + MCP 外部连接

```text
chrome.service
    │
    ├── persistent profile
    └── 127.0.0.1:9222
             ↑
             │
chrome-devtools-mcp
    --browser-url=http://127.0.0.1:9222
```

这样做的理由：

1. 登录态不绑定单次 Agent 会话；
2. MCP 可以独立升级/重启；
3. 人工登录与 Agent 自动操作可以共享同一专用 profile；
4. Chrome 故障和 MCP 故障可以独立诊断。

Chrome 启动至少满足：

```text
remote debugging address: localhost
remote debugging port: 9222（可配置）
user data dir: 专用、非默认、持久化目录
```

具体启动参数由后续 `deploy/chrome/` 固化，不在架构文档里把临时命令当作生产 SSOT。

## 5. 有界面与 Headless

首个小红书 Pilot 推荐保留可人工接管的浏览器界面：

```text
Chrome
↓
Xvfb / desktop session
↓
可选 noVNC / 受控远程桌面
```

用途：

- 第一次正常登录；
- 查看登录失效页面；
- 人工确认站点交互状态；
- 调试页面结构变化。

稳定以后可以验证 headless 是否满足具体来源场景，但不能把“无界面”当成架构目标。

## 6. Chrome DevTools MCP

上游：

<https://github.com/ChromeDevTools/chrome-devtools-mcp>

当前官方文档支持连接已运行 Chrome：

```text
--browser-url=http://127.0.0.1:9222
```

开发验证可以使用 `npx chrome-devtools-mcp@latest`，但生产部署必须固定一个已经通过本仓库 Pilot 的版本。

版本策略：

```text
candidate version
↓
staging smoke test
↓
XHS pilot regression
↓
pin version
↓
production
```

不让 unattended restart 自动漂移到新的 `latest`。

## 7. Remote MCP 入口

网页版 ChatGPT 连接的是远程 MCP，不是服务器本地 stdio 进程。

因此部署必须包含：

```text
ChatGPT-compatible remote MCP endpoint
              ↓
MCP gateway / bridge
              ↓
Chrome DevTools MCP local process
```

私网部署优先使用 OpenAI 当前支持的 Secure MCP Tunnel，或等价的受控远程接入方案。

Gateway 第一阶段的职责只包括：

- transport 适配；
- 子进程生命周期；
- 请求/错误转发；
- 健康检查；
- 最小必要日志。

不把 XHS 页面规则塞进 Gateway。

## 8. 出站网络

Chrome 是否需要 Proxy/TUN 与 Remote MCP 接入是独立配置。

支持模式：

```text
Chrome → Direct → Internet
Chrome → HTTP/SOCKS proxy → Internet
Chrome → host TUN → Internet
```

部署脚本需要允许显式选择，不默认假设服务器必须经过代理。

## 9. systemd 单元建议

预期至少拆分：

```text
source-chrome.service
source-mcp-gateway.service
source-mcp-tunnel.service
```

如果使用独立虚拟桌面或网络代理，再增加对应 service。

不要把所有组件塞进一个无法区分故障原因的 shell 常驻进程。

依赖方向：

```text
network ready
↓
Chrome / optional display
↓
MCP gateway
↓
Tunnel
```

但健康检查必须能区分：Chrome 活着、CDP 可用、MCP 可用、Tunnel 已连通这几个不同事实。

## 10. 部署验收顺序

必须逐层证明，不使用“最终请求成功”掩盖中间边界问题。

### Gate A：Chrome

确认：

- Chrome 进程正常；
- 使用专用 profile；
- CDP 仅在本机可达；
- 页面可以正常访问普通网站。

### Gate B：Chrome DevTools MCP

确认：

- MCP 能连接目标 Chrome；
- 能列出/创建页面；
- 能读取页面快照；
- MCP 重启后 Browser Profile 保持。

### Gate C：远程 MCP transport

确认：

- Gateway 可以启动/连接本地 MCP；
- 远程 MCP 客户端可以枚举工具；
- 工具调用错误保持可诊断，不被统一吞成 timeout。

### Gate D：Tunnel

确认：

- ChatGPT 侧可以看到目标 MCP；
- Tunnel 断开时不会影响 Chrome profile；
- 重连后不需要重新登录网站。

### Gate E：真实来源

确认：

- 人工完成一次小红书正常登录；
- Agent 能执行搜索；
- Agent 能打开一篇笔记；
- 能形成完整 Source Artifact；
- 不把后续 AI 分析混入 Raw capture。

## 11. 部署产物规划

后续实现推荐形成：

```text
deploy/
├── chrome/
│   ├── install.sh
│   └── source-chrome.service
├── chrome-devtools-mcp/
│   ├── install.sh
│   └── version.env
├── gateway/
│   └── ...
├── tunnel/
│   └── ...
└── network/
    └── ...

scripts/
├── install
├── start
├── stop
├── status
└── doctor
```

`doctor` 最终应该成为部署后的主要诊断入口，而不是要求用户手工执行大量底层命令。

## 12. 暂不决定

首批文档暂不锁死：

- Gateway 的具体实现项目；
- Secure MCP Tunnel 与公网 HTTPS 两种接入是否都长期支持；
- Docker 还是纯 systemd 成为默认发行形态；
- Artifact 最终使用 Git、对象存储还是本机 CAS。

这些必须通过第一个端到端 Pilot 再决定。