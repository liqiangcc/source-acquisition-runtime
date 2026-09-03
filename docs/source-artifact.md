# Source Artifact 契约

## 1. 目的

Runtime 的价值不是“让 AI 看过网页”，而是把一次网页获取变成可追溯、可重复引用的 Source Capture。

因此领域系统与 Runtime 之间通过 Source Artifact 交接，而不是通过一段临时聊天文本交接。

## 2. 基本模型

```text
Source
└── SourceRevision
    ├── identity
    ├── original URL
    ├── capture metadata
    ├── raw artifacts
    ├── projections
    ├── integrity metadata
    └── limitations
```

同一个来源以后重新捕获时创建新 revision，不静默覆盖旧 revision。

## 3. Stable Source Identity

优先使用来源平台自身稳定 identity：

```text
xhs:<note_id>
nowcoder:<post_id>
github:<owner>/<repo>@<object>
```

普通网页如果没有平台稳定 id，可以使用 canonical URL 派生 identity，但必须保留原始 URL。

Identity 不应该依赖：

- GitHub Issue number；
- 本地文件路径；
- AI 总结标题；
- 采集顺序；
- 当前页面 DOM index。

## 4. Revision Identity

建议：

```text
<source_id>:<capture_revision>
```

例如：

```text
xhs:abcdef:r1
xhs:abcdef:r2
```

具体 revision 编码以后可以调整，但必须满足：

- 唯一；
- 不可变；
- 可追溯到一次具体 capture；
- 新 capture 不修改旧 bytes。

## 5. Artifact 分类

### Raw Artifact

能够作为第一手证据保存的内容，例如：

```text
captured page / HTML
original image bytes
network-fetched source bytes（如果由浏览器正常页面流程获得）
source-provided attachment
```

### Source Projection

为了读取方便从 Raw 生成的内容，例如：

```text
readable text
normalized metadata JSON
DOM-derived article text
```

Projection 必须指向对应 Raw revision。

### Derived

不属于 Runtime Source truth 的内容，例如：

```text
OCR interpretation
AI summary
interview question extraction
company / role classification
answer
training analysis
```

如果 Runtime 为方便消费生成 OCR，它也必须明确标为 Derived/Projection，不能冒充原始图片。

## 6. 建议 Manifest

第一版可以使用一个简单 JSON manifest：

```json
{
  "schema_version": "source-capture.v1",
  "source_id": "xhs:example",
  "source_revision_id": "xhs:example:r1",
  "source_system": "xhs",
  "original_url": "https://example.invalid/note/example",
  "discovered_at": "2026-09-03T00:00:00Z",
  "captured_at": "2026-09-03T00:01:00Z",
  "artifacts": [
    {
      "kind": "page",
      "provenance": "raw_capture",
      "ref": "artifacts/page.html",
      "sha256": "...",
      "size": 12345
    },
    {
      "kind": "image",
      "provenance": "raw_capture",
      "ref": "artifacts/images/1.webp",
      "sha256": "...",
      "size": 23456
    },
    {
      "kind": "text_projection",
      "provenance": "source_projection",
      "ref": "projection/readable.txt",
      "sha256": "...",
      "size": 3456
    }
  ],
  "metadata": {
    "title": null,
    "author": null,
    "published_at": null
  },
  "limitations": []
}
```

示例中的 URL、hash 和 size 只是 schema 演示，不代表真实数据。

## 7. Metadata 的证据语义

Metadata 也必须区分：

```text
Source directly observed
vs
Agent inferred
```

Runtime manifest 只保存可以从当前 Source capture 直接追溯的字段。

例如：

```text
页面直接给出发布日期 → 可以保存
AI 根据“秋招”猜年份 → 不保存成 Source fact
```

不确定字段保持 `null` 或附带明确 precision / limitation。

## 8. 图片

图片型面经是首个 Pilot 的关键情况。

需要保存：

```text
图片在页面中的顺序
原始图片 URL（可获得时）
实际保存的 image bytes
sha256
size
content type
```

如果只能确认页面引用了图片，但没有成功得到 bytes：

```text
image reference exists
image bytes missing
```

这是合法 limitation，不能生成伪造图片或用 OCR 文本替代原图证据。

## 9. 页面快照

不同网站和 Chrome DevTools MCP 能力可能提供不同形式：

- DOM/page snapshot；
- HTML；
- rendered text；
- screenshot；
- network response。

第一版不强制“Raw 必须等于某一种 HTML 文件”。

更重要的规则是：

> Manifest 必须准确说明保存了什么、它从哪里来、它能证明什么。

如果页面本身无法导出完整原始 HTML，就不要把局部 DOM snapshot 命名成 `raw-original-html`。

## 10. Storage Ref

Artifact 存储后端第一阶段保持可替换：

```text
local filesystem
Git repository
object storage
content-addressed storage
```

领域系统引用的是：

```text
source_revision_id
+
artifact ref
+
hash
```

而不把某个本地绝对路径当作长期 identity。

## 11. 与 interview-lab 的交接

目标链路：

```text
source-acquisition-runtime SourceCapture
↓
source integrity review
↓
interview-lab InterviewNote
```

`interview-lab` 可以登记：

- `source.system`；
- `source.external_id`；
- 原始 URL；
- SourceRevision；
- Raw Artifact refs；
- Projection refs；
- limitations。

之后 InterviewContext、SourceQuestion、Analysis 等全部属于下游 Derived。

## 12. Fail-closed

以下情况不得声明 capture 完整：

- source identity 不确定；
- 页面明显截断但未记录；
- 图片顺序无法确认；
- 预期图片缺失且未记录；
- projection 无法追溯到本次 revision；
- hash 与实际文件不匹配；
- 多个来源 artifact 被错误混入同一个 revision。

Source 不完整并不意味着 capture 失败；可以产出带 limitation 的有效 revision。

## 13. 第一版最小字段

真正 MVP 只要求：

```text
schema_version
source_id
source_revision_id
source_system
original_url
captured_at
artifacts[] {kind, provenance, ref, sha256, size}
limitations[]
```

其他字段由真实 Pilot 证明价值后再扩展。