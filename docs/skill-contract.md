# Source Acquisition Skill 契约

## 1. Skill 的定位

Skill 是“AI 如何组合浏览器原子能力完成一次 Source Acquisition”的可审计操作规范。

```text
Chrome DevTools MCP
= 原子浏览器能力

Skill
= 获取某类 Source 的步骤、判断、输出与失败边界
```

Skill 不是：

- Chrome DevTools MCP 的 fork；
- 大量平台选择器硬编码的别名；
- 面经领域分析 Prompt；
- Source truth 数据库。

## 2. 为什么需要 Skill

如果只把低层浏览器工具暴露给 AI，每次 Agent 都可能重新发明：

```text
怎么搜索
怎么判断结果页加载完成
怎么确定当前笔记 identity
正文从哪里读
图片顺序怎么保存
失败时记录什么
```

Skill 把这些经验变成仓库版本化的执行规范，同时仍允许底层 Chrome DevTools MCP 独立升级。

## 3. Skill 文件建议结构

```text
skills/
└── xhs/
    ├── discover-interview-notes/
    │   └── SKILL.md
    └── capture-note/
        └── SKILL.md
```

后续普通网页可以增加：

```text
skills/web/capture-page/SKILL.md
```

## 4. 每个 Skill 必须声明

### Identity

```text
name
version
purpose
```

### Inputs

例如 discovery：

```text
keyword
optional time hint
optional maximum candidates
```

例如 capture：

```text
source URL or stable source id
```

### Preconditions

例如：

```text
Chrome reachable
MCP reachable
site session valid
expected domain loaded
```

### Allowed capability classes

例如：

```text
navigation
page snapshot
DOM reading
JavaScript evaluation
network inspection
screenshot
```

Skill 不依赖一次运行中某个临时 tool-call id。

### Procedure

描述稳定的语义步骤，而不是把所有 DOM selector 当成永恒协议。

### Output

必须输出 Source Candidate 或 Source Capture，而不是只输出自然语言总结。

### Validation

定义完成前必须证明什么。

### Failure / Limitation

定义遇到不完整信息时如何停止或降级。

## 5. Discovery Skill 输出

Discovery 只负责发现候选，不直接声称 Source capture 完整。

建议输出：

```json
{
  "source_system": "xhs",
  "external_id": "...",
  "url": "...",
  "title": "...",
  "discovered_at": "...",
  "discovery_evidence": "..."
}
```

Discovery 不做：

```text
InterviewContext
Question extraction
Answer generation
```

## 6. Capture Skill 输出

Capture 必须形成 `docs/source-artifact.md` 定义的 SourceRevision。

最低输出：

```text
source_id
source_revision_id
original_url
raw artifact refs
projection refs
hashes
limitations
```

不能只返回：

> “这篇面经主要问了 Redis、MySQL 和线程池。”

这种信息属于下游解释，不是 capture 输出。

## 7. Browser State 规则

Skill 每个关键阶段都从浏览器当前状态取证，不能假设：

```text
上一次 tool call 的 tab 仍然是当前 tab
页面没有发生跳转
人工接管期间页面没有改变
登录状态永久有效
```

发生人工接管、navigation 或异常恢复后，必须重新确认：

```text
current URL
page identity
expected page type
```

## 8. Selector 策略

网页结构会变化。

Skill 优先依赖：

1. 可见语义和稳定页面角色；
2. 稳定 URL / platform identity；
3. 页面中可验证的结构关系；
4. 最后才是易变的 CSS class / DOM path。

如果必须依赖平台选择器，应在 Skill 中标记为：

```text
site-specific assumption
```

真实页面变化导致假设失效时，Skill 应失败并留下诊断，而不是返回看起来成功的错误 Source。

## 9. 不确定性规则

Skill 只能把浏览器当前 capture 可以证明的信息写入 Source metadata。

例如：

```text
页面显示“9.18”
```

不能因为发布时间看起来属于 2026 秋招，就自动写：

```text
interview_occurred_at = 2026-09-18
```

这种领域推断必须留给下游，并保持 Source 自身精度。

## 10. 图片规则

对于图片承载主要内容的平台：

```text
页面引用顺序
↓
实际图片 bytes
↓
hash/size
↓
可选 readable projection/OCR
```

如果只拿到图片 URL 没拿到 bytes，明确记录 limitation。

OCR 无论多准确都不自动升级成 Raw Source。

## 11. Skill 与网页版 ChatGPT

仓库中的 `SKILL.md` 本身不会天然变成网页版 ChatGPT 的 MCP tool。

第一阶段有两种使用形态：

### A. 透明低层 MCP + Agent 执行 Skill

```text
ChatGPT / compatible agent
↓
读取/遵循 Skill 规范
↓
调用 Chrome DevTools MCP 原子工具
```

### B. 后续高层 façade

如果真实 Pilot 证明网页版客户端难以稳定执行低层步骤，再把成熟 Skill 提升为高层工具：

```text
source_discover
source_capture
```

高层工具内部仍遵循同一个 Source Artifact contract。

是否建设 B 由 Pilot 决定，不提前假定必须自研完整 MCP Server。

## 12. Skill 版本与兼容性

Skill 变化必须可审计。

建议：

```text
skill version
validated Chrome version
validated chrome-devtools-mcp version
last real pilot date
known site assumptions
```

不要因为网页临时变化直接覆盖历史结论而不记录。

## 13. 第一批 Skill

只创建两个：

```text
xhs/discover-interview-notes
xhs/capture-note
```

先证明：

```text
搜索 → 发现 → 打开 → capture → artifact
```

5 篇真实面经闭环后，再判断是否需要：

```text
xhs/recover-images
xhs/review-capture
nowcoder/discover-interview-notes
web/capture-page
```

## 14. Skill 验收

一个 Skill 不是“Agent 成功跑过一次”就成熟。

至少检查：

- 成功路径；
- 页面无结果；
- Session 失效；
- 页面结构变化；
- 图片不完整；
- 重复 Source；
- navigation 后 identity 保持；
- 失败时没有生成伪成功 Artifact。

目标是可靠获取 Source，而不是追求一次 demo 的自动化长度。