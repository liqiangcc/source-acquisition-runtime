# 小红书真实面经 Pilot

## 1. Pilot 目标

首个 Pilot 不追求采集数量。

要验证的是：

> 网页版/远程 MCP 客户端能否通过本仓库部署的 Runtime 使用服务端 Chrome，在已有正常登录态下发现并获取真实小红书面经，形成可追溯 Source Artifact，并交给 `interview-lab`。

成功标准是完整闭环，不是“能打开小红书”。

## 2. Pilot 范围

第一轮只处理 5 篇真实面经。

候选应尽量覆盖：

```text
1 篇正文为主
1 篇图片为主
1 篇正文 + 图片混合
1 篇多图且顺序重要
1 篇存在信息不完整或边界情况
```

这样可以尽早验证 Source Artifact 契约，而不是只挑最容易的页面。

## 3. 关键词

第一阶段优先使用和 `interview-lab` 当前目标一致的关键词，例如：

```text
Java 后端 面经
Java 社招 面试
后端 二面 面经
快手 Java 面经
字节 Java 面经
```

关键词只是 discovery 输入，不进入 Source identity。

## 4. 前置条件

Pilot 开始前必须通过部署 Gate：

```text
Chrome PASS
CDP localhost PASS
Chrome DevTools MCP PASS
MCP Gateway PASS
Remote MCP / Tunnel PASS
Chrome outbound network PASS
```

并由用户在专用 Browser Profile 中完成正常小红书登录。

如果登录状态失效，Pilot 标记 `manual-login-required`，先恢复 Session，再继续。

## 5. Discovery

执行：

```text
打开小红书
↓
确认当前登录状态
↓
搜索关键词
↓
读取搜索结果
↓
识别候选 note
↓
登记 stable external id / URL / title
↓
输出 candidate
```

Candidate 至少包括：

```text
source_system = xhs
external_id
url
title
discovered_at
```

如果当前页面无法稳定确认 external id，保留 URL candidate，但不能伪造 stable id。

## 6. 去重

Capture 前先检查下游已有 Source identity。

首个对接目标是 `liqiangcc/interview-lab`。

如果：

```text
xhs:<note_id>
```

已经存在，则：

```text
不是新 InterviewNote
```

可以选择：

- 跳过；
- 如果当前 capture 明显更完整，则作为潜在新 SourceRevision 进入 review。

不能因为 URL 参数或页面标题变化就创建 duplicate note。

## 7. Capture

对每篇候选执行：

```text
打开 note
↓
确认 URL / note identity
↓
保存当前页面 Source capture
↓
提取可读正文 projection
↓
枚举原始图片及页面顺序
↓
保存可以正常获取的图片 bytes
↓
记录 title / author / published time 等可直接观察 metadata
↓
计算 hash / size
↓
登记 limitations
↓
生成 source-capture.v1 manifest
```

## 8. Capture 不做什么

Pilot capture 阶段不做：

```text
把面经拆成问题
判断问题知识领域
补标准答案
判断作者面试表现
推测公司岗位
提前读取结果影响前面内容解释
```

这些属于 `interview-lab` 后续 Derived 层。

## 9. 图片型内容

如果详细面试题主要存在图片里：

```text
Raw image bytes
= 证据根

OCR / readable transcription
= Derived projection
```

Pilot 必须至少验证一个图片主导 case，确认 Runtime 不会只抓正文然后漏掉真正的面经问题。

每张图至少登记：

```text
sequence
source/ref URL（可获得时）
artifact ref
content type
size
sha256
```

## 10. 时间字段

只保存页面直接证明的来源时间事实。

如果正文写：

```text
9.18 面试
```

但没有明确年份，则 Runtime 不把年份补进去。

`interview-lab` 已经有更完整的时间模型，Runtime 只需要保真传递 Source fact。

## 11. Source Review

每个 Pilot Source 在交给 `interview-lab` 前至少检查：

```text
source identity 是否稳定
URL 是否属于当前 note
页面正文是否明显截断
图片数量和顺序是否合理
已登记图片 bytes 是否真实非空
hash/size 是否一致
projection 是否可追溯到 Raw
未知和缺失是否进入 limitations
是否混入另一个 note 的 artifact
```

## 12. 与 interview-lab 的交接

推荐链路：

```text
Runtime SourceCapture
↓
Source integrity review
↓
interview-lab create/reconcile InterviewNote
↓
status:captured
↓
source-review
↓
source-ready / blocked
↓
InterviewContext
↓
Learning Discovery
```

Runtime 不直接跳过 `interview-lab` 的 Source lifecycle。

## 13. Pilot 数据目录建议

实现阶段可以先使用：

```text
/var/lib/source-acquisition-runtime/artifacts/
└── xhs/
    └── <note_id>/
        └── r1/
            ├── manifest.json
            ├── raw/
            │   ├── page.*
            │   └── images/
            └── projection/
                └── readable.txt
```

最终 storage backend 尚未锁定，目录结构不是长期 identity。

## 14. 失败案例也属于 Pilot 结果

以下结果不是“无效测试”：

- 某篇只能获得正文，图片 bytes 无法获得；
- Session 中途失效；
- 搜索结果能看到但打开后 note 不可访问；
- 页面更新导致 Skill 假设失效；
- external id 无法稳定取得。

这些情况应产生明确 failure class / limitation，用来决定下一步真正需要建设什么机制。

## 15. Pilot 完成条件

5 篇 case 完成后，必须能够回答：

### Runtime

- 裸服务器部署能否重复执行？
- Chrome Profile 是否稳定保持？
- MCP/Tunnel 重连是否影响浏览器状态？

### Browser automation

- Search 是否稳定？
- Note identity 是否稳定？
- 正文和图片是否都能捕获？

### Source integrity

- Raw / Projection 边界是否足够？
- Artifact hash / limitation 是否足够定位问题？

### Domain handoff

- `interview-lab` 是否可以不关心 Chrome 细节直接消费 SourceCapture？
- create/reconcile 是否能避免 duplicate？

## 16. Pilot 后的决策门

只有 Pilot 结束后再决定是否需要：

```text
A. 继续使用 Chrome DevTools MCP 原子工具 + Skills
B. 增加轻量高层 Source Acquisition MCP façade
C. 引入稳定平台 adapter
D. 引入 Artifact 对象存储
E. 扩展到牛客等第二个平台
```

如果 5 篇 Pilot 已经可以可靠闭环，就不因为“架构看起来还能更完整”继续增加层次。

## 17. 最终用户体验目标

目标交互应接近：

```text
用户：找最近的快手 Java 后端二面面经。

AI：
→ 通过 MCP 使用服务端 Chrome
→ 搜索小红书
→ 返回候选
→ 获取用户选择的 Source
→ 形成可追溯 Artifact
→ 交给 interview-lab

用户：开始第一篇。
```

从这一刻开始，用户不再需要关心 Chrome、CDP、Tunnel、Artifact 路径等底层细节。