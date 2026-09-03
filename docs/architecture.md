# 总体架构

## 1. 目标

本仓库解决一个基础设施问题：

> 如何让 AI 从远程客户端通过 MCP 使用一台服务端浏览器，获取外部网页的第一手 Source，并把可追溯 Artifact 交给领域系统。

首个目标客户端是网页版 ChatGPT，首个真实数据源是小红书面经，首个下游领域系统是 `interview-lab`。

这三个具体对象都不是架构边界本身。架构需要允许未来替换客户端、浏览器执行器、来源平台和下游消费者。

## 2. 分层

```text
┌─────────────────────────────────────┐
│ AI Client                           │
│ ChatGPT Web / other MCP clients     │
└──────────────────┬──────────────────┘
                   │ remote MCP
┌──────────────────▼──────────────────┐
│ Remote Access Layer                 │
│ Secure MCP Tunnel / controlled edge│
└──────────────────┬──────────────────┘
                   │
┌──────────────────▼──────────────────┐
│ MCP Transport / Gateway Layer       │
│ remote transport ↔ local MCP        │
└──────────────────┬──────────────────┘
                   │ local stdio
┌──────────────────▼──────────────────┐
│ Browser Capability Layer            │
│ Chrome DevTools MCP                 │
└──────────────────┬──────────────────┘
                   │ CDP localhost
┌──────────────────▼──────────────────┐
│ Browser Runtime                     │
│ Chrome + persistent profile         │
└──────────────────┬──────────────────┘
                   │
┌──────────────────▼──────────────────┐
│ External Sources                    │
│ Web / XHS / Nowcoder / ...          │
└──────────────────┬──────────────────┘
                   │
┌──────────────────▼──────────────────┐
│ Source Artifact Layer               │
│ raw + projection + provenance       │
└──────────────────┬──────────────────┘
                   │
┌──────────────────▼──────────────────┐
│ Domain Consumers                    │
│ interview-lab / reading / others    │
└─────────────────────────────────────┘
```

## 3. 关注分离点

### 3.1 Chrome DevTools MCP 只提供浏览器原子能力

Chrome DevTools MCP 负责页面导航、DOM/页面快照、网络观察、JavaScript 执行、截图等浏览器能力。

它不需要理解：

- 什么叫“面经”；
- 哪一篇内容值得采集；
- `InterviewNote` 是什么；
- Source Artifact 应该如何进入 `interview-lab`；
- 用户下一步应该练哪道题。

因此本仓库不 fork Chrome DevTools MCP 加入 `xhs_search`、`interview_capture` 一类领域工具。

### 3.2 Skill 定义采集语义

Skill 定义“为了获得某类 Source，Agent 应如何组合浏览器能力、检查输出并形成 Artifact”。

例如：

```text
xhs-interview-discovery
xhs-note-capture
web-page-capture
```

Skill 属于策略层，不拥有浏览器实现。

第一阶段 Skill 可以只是 AI 可执行的仓库规范；只有真实 Pilot 证明低层工具组合过于脆弱时，才考虑增加稳定的高层 MCP façade。

### 3.3 Runtime 负责部署，不负责领域解释

Runtime 可以知道：

- Chrome 安装在哪里；
- Profile 保存在哪里；
- MCP 如何启动；
- Tunnel 如何连接；
- Artifact 如何写入存储。

Runtime 不应该判断：

- 某个 Java 问题正确答案是什么；
- 某篇面经对应什么 CanonicalQuestion；
- 某个面试结果意味着什么。

这些进入 `interview-lab` 后再处理。

### 3.4 Raw Source 与 Projection 分层

```text
Raw Source
├── captured HTML / page representation
├── original image bytes
├── original URL
└── capture metadata

Projection
├── readable text
├── normalized metadata
└── OCR（需要时）

Domain Derived
├── InterviewContext
├── SourceQuestion
├── Analysis
└── Answer / Training
```

Projection 不能覆盖 Raw；Domain Derived 更不能反向修改 Raw。

## 4. 两条网络链必须分开

### 入站控制面

```text
ChatGPT
↓
Remote MCP / Tunnel
↓
MCP Gateway
↓
Chrome DevTools MCP
```

解决“远程 AI 怎么调用本地 MCP”。

### 出站数据面

```text
Chrome
↓
Direct / HTTP Proxy / SOCKS / TUN
↓
Internet
```

解决“服务器上的浏览器如何访问目标网站”。

二者独立部署、独立排障、独立健康检查。不能用“Tunnel”一个词同时指代两者。

## 5. Chrome / CDP 边界

推荐生产形态：

```text
Chrome
  remote debugging: 127.0.0.1:9222
          ↑
          │ localhost
Chrome DevTools MCP
```

Chrome 官方当前要求 remote debugging 使用非默认 user data directory；Chrome DevTools MCP 官方也支持用 `--browser-url=http://127.0.0.1:9222` 连接已经运行的 Chrome。

设计不变量：

1. `9222` 不作为公网服务；
2. `9222` 不直接接 Remote MCP Tunnel；
3. Browser Profile 是独立的采集 profile；
4. Browser Profile 生命周期独立于单次 MCP 会话；
5. MCP 重启不应该自然导致登录态丢失。

## 6. Transport 兼容层

Chrome DevTools MCP 主要以本地 MCP 进程方式被客户端启动。网页版 ChatGPT 则要求远程 MCP 连接；OpenAI 当前文档明确指出，本机/私网 MCP 不能被 ChatGPT 直接连接，私网场景可使用 Secure MCP Tunnel。

因此 Runtime 必须显式拥有一个 transport 边界：

```text
remote MCP transport
        ↕
transport bridge / gateway
        ↕
Chrome DevTools MCP local transport
```

这个组件第一阶段应尽可能透明，只做 transport 和生命周期适配，不重新定义浏览器语义。

如果未来 Chrome DevTools MCP 原生提供满足目标客户端要求的远程 transport，可以删除这一层，而不影响 Skill 和 Source Artifact 契约。

## 7. Artifact 边界

Runtime 的最终输出不是“AI 看懂了网页”，而是：

```text
SourceCapture
├── source identity
├── source revision
├── original URL
├── raw artifacts
├── readable projections
├── hashes / sizes
├── capture metadata
└── limitations
```

领域系统只消费这个稳定边界。

## 8. 不提前建设的能力

首个 Pilot 前不建设：

- 通用爬虫 DSL；
- 多租户浏览器调度系统；
- 自动验证码处理系统；
- 大规模并发采集队列；
- 平台反向 API 兼容层；
- 自研浏览器自动化协议；
- 复杂通用 Source Knowledge Graph。

只有真实 Pilot 暴露 correctness、provenance、并发或可维护性问题后，再增加对应机制。

## 9. 当前决策

```text
Chrome DevTools MCP = 浏览器能力执行器
source-acquisition-runtime = 部署 + 网络 + profile + skill + artifact contract
interview-lab = 面经领域消费方
```

这是当前阶段的主分离点。