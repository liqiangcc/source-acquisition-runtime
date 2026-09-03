# Source Acquisition Runtime

`source-acquisition-runtime` 是一套让 AI 通过 MCP 获取外部第一手 Source 的可部署运行环境。

首个真实场景是：**网页版 ChatGPT 通过 MCP 使用服务端 Chrome，在已有正常登录态下发现并获取小红书真实面经，并把可追溯 Source 交给 `interview-lab`。**

本仓库不重新实现 Chrome DevTools MCP。它负责把浏览器执行环境、MCP 连接、远程访问链路、Source Acquisition Skills 和 Source Artifact 边界组合成一个可部署、可验证、可演进的 runtime。

## 核心架构

```text
ChatGPT Web
    │
    │ Remote MCP / Secure MCP Tunnel
    ▼
MCP Gateway / Transport Bridge
    │
    │ local stdio
    ▼
Chrome DevTools MCP
    │
    │ CDP on localhost only
    ▼
Chrome
    │
    ▼
Web / XHS / other sources
```

浏览器访问互联网的出站网络与 ChatGPT 访问 MCP 的入站网络是两条独立链路：

```text
入站控制面：ChatGPT → MCP Tunnel → MCP Gateway
出站数据面：Chrome → Proxy/TUN/Direct → Internet
```

Chrome remote debugging 端口只保留在 runtime 本机可信边界内，不作为远程 MCP 入口。

## 仓库职责

本仓库负责：

- 服务端 Chrome 的安装、启动、升级与健康检查；
- 独立且持久化的 Browser Profile；
- Chrome DevTools MCP 的安装、配置与版本管理；
- 将本地 MCP transport 接到网页版 ChatGPT 可访问的远程 MCP 入口；
- Secure MCP Tunnel / 其他受控远程接入方式的部署配置；
- Chrome 出站 Proxy/TUN 的独立配置；
- Source Acquisition Skills；
- Raw Source、Projection、Provenance 和 Artifact 输出契约；
- 真实网站 Pilot、故障分类和验收规则。

本仓库不负责：

- 把 Chrome DevTools MCP fork 成业务 MCP；
- 面经问题提取、答案生成和训练逻辑；
- 替代 `interview-lab` 的 InterviewNote / Source lifecycle；
- 把网页内容直接解释成领域事实。

## 与其他仓库的边界

```text
source-acquisition-runtime
        │
        │ 获取并保存 Source
        ▼
interview-lab
        │
        │ InterviewNote / Context / Training
        ▼
面试训练与知识沉淀
```

对于书籍、论文或普通网页，后续也可以把这里产生的 Source Artifact 交给其他领域系统消费。

## 第一阶段目标

第一阶段只验证最短闭环：

```text
裸 Linux 服务器
↓
安装 Chrome
↓
建立持久 Browser Profile
↓
人工完成小红书正常登录
↓
Chrome DevTools MCP 连接本机 Chrome
↓
远程 MCP 链路可被 ChatGPT 使用
↓
AI 搜索一篇小红书面经
↓
获取正文、页面元数据和原始图片
↓
生成可追溯 Source Artifact
↓
交给 interview-lab
```

先完成 5 篇真实面经 Pilot，再决定是否增加平台专用工具或更高层 Source Acquisition MCP façade。

## 文档

- `docs/architecture.md`：总体架构与关注分离点
- `docs/deployment.md`：服务端部署目标与验收顺序
- `docs/networking.md`：Remote MCP、Tunnel、CDP 与出站 TUN/Proxy 边界
- `docs/browser-profile.md`：持久登录态与人工接管规则
- `docs/source-artifact.md`：Raw Source / Projection / Provenance 契约
- `docs/skill-contract.md`：Source Acquisition Skill 契约
- `docs/xhs-pilot.md`：首个小红书真实面经 Pilot

## 当前设计原则

1. **浏览器能力与采集语义分离。** Chrome DevTools MCP 提供原子浏览器能力，Skill 定义如何获取 Source。
2. **部署与领域知识分离。** Runtime 负责把 Source 带进来，领域仓库负责理解 Source。
3. **Raw 与 Derived 分离。** HTML、图片等第一手 artifact 不被 OCR、摘要或 AI 判断覆盖。
4. **证据优先。** 每个 Source 保留稳定 identity、原始 URL、capture revision、artifact ref/hash 与 limitation。
5. **CDP 最小暴露。** Remote debugging 只在本机可信边界中使用。
6. **登录态专用。** 采集浏览器使用独立 profile，不与个人日常浏览 profile 混用。
7. **Fail closed。** Source 不完整、identity 冲突或 provenance 不足时记录 limitation，不补造缺失事实。
8. **Pilot 驱动抽象。** 没有真实失败证明需要时，不提前构建大型平台框架。

## 上游参考

- Chrome DevTools MCP：<https://github.com/ChromeDevTools/chrome-devtools-mcp>
- Chrome DevTools MCP Advanced Usage：<https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/advanced-usage.md>
- OpenAI Developer mode and MCP apps：<https://help.openai.com/en/articles/12584461>

> 上游 MCP、Chrome 与 ChatGPT 接入能力可能演进。仓库中的部署脚本应固定经过验证的版本；文档描述的是边界和验收条件，不把 `latest` 当作生产版本策略。
