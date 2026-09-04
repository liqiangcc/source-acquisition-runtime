# linux-primary-01 — `navigate_page` false-negative timeout

## 现象

在真实 XHS 页面导航中，`chrome-devtools-mcp 1.8.0` 可能返回：

```text
Unable to navigate in the selected page: Navigation timeout of <N> ms exceeded.
```

但紧接着 `list_pages` / `take_snapshot` 已经显示目标 URL 和目标页面内容。

## 分层排查

问题可绕过 Secure MCP Tunnel、只经 localhost Gateway 稳定复现，因此 Tunnel 不是必要条件。

本机 1.8.0 实现中，`navigate_page(type=url)` 调用：

```text
page.waitForEventsAfterAction(...)
  -> page.pptrPage.goto(requested_url, timeout)
```

`page.goto()` 在等待 Puppeteer 导航完成条件超时时会抛出 `Navigation timeout`。此时浏览器可能已经完成主文档切换，`page.url()` 已经等于请求 URL。

原实现捕获异常后直接输出 `Unable to navigate...`，没有核验最终 URL，因此形成 false-negative。

## 修复语义

`source-acquisition-runtime` 对固定版本 `chrome-devtools-mcp 1.8.0` 应用一个 fail-closed compatibility patch：

1. 仅处理 `navigate_page(type=url)`；
2. 仅处理 Puppeteer `Navigation timeout`；
3. timeout 后读取 `page.url()`；
4. 去除 fragment 后，只有最终 URL 与请求 URL 精确一致时，返回 verified partial-success：

```text
Navigation reached the requested URL, but load completion timed out: ... Verify page state before retrying.
```

5. URL 不一致、重定向到其它页面、其它异常继续保持原始失败语义。

这避免 Agent 因 false-negative 盲目重复导航，同时不会把登录重定向、404 或其它页面误判为成功。

## 可重复回归

`scripts/navigate-timeout-smoke.mjs` 在 localhost 启动一个故意延迟 `load` 完成的 HTTP 页面：

```text
new_page about:blank
-> navigate_page timeout=1000ms
-> 浏览器先到达目标 URL
-> HTTP response 延迟结束
-> Puppeteer goto 超时
-> runtime 必须报告 reached-target partial-success
-> list_pages 必须确认最终 URL 等于请求 URL
```

该回归不依赖 XHS、外网或 Secure MCP Tunnel。

## 升级边界

Compatibility patch 只允许应用于 `chrome-devtools-mcp 1.8.0`。如果版本变化或预期代码块不再唯一匹配，安装必须 fail-closed，先重新审核 upstream 行为，不能静默把旧 patch 套到新版本。

## Root Cause Analysis（2026-09-04）

Compatibility patch 解决的是“timeout 后不要误判并盲目重试”，但它不是根因本身。随后使用 Chrome 原生 CDP 对真实 XHS 页面做时间线采样，并把 Secure MCP Tunnel、Gateway 与 MCP tool 层全部绕开。

### 网络基线

目标机当前网络基线没有显示持续性主站网络慢：

```text
www.xiaohongshu.com direct:
  DNS ~16ms, TLS ~563ms, TTFB ~670ms, total ~858ms

www.xiaohongshu.com via 127.0.0.1:7890:
  TLS ~144ms, TTFB ~274ms, total ~455ms

XHS image CDN:
  TLS / TTFB 为几十毫秒级
```

Chrome service 没有显式 `--proxy-server` 参数。因此“基础 DNS/TCP/TLS/主文档长期很慢”不能解释本次 10–15 秒 Navigation timeout。

### 真实 XHS CDP 时间线

同一个 XHS note，重启 Chrome 前 5 次：

```text
main document response: 187–530ms, median 208ms
DOMContentLoaded:        1.85–3.16s, median 2.08s
window.load:             7.45–11.77s, median 8.31s, mean 8.76s
```

释放部分资源压力并重启 Chrome 后 5 次：

```text
main document response: 168–304ms, median 186ms
DOMContentLoaded:        1.56–4.32s, median 1.78s
window.load:             5.82–9.42s, median 6.52s, mean 6.92s
```

主文档几百毫秒就返回，真正的长尾发生在 `DOMContentLoaded -> window.load`。

### 最后阻塞 load 的资源

对 load-sensitive request 记录 initiator 后，3 次样本都指向由 XHS webpack runtime 动态加载的晚发 chunk：

```text
1863.b78bffb0.js
799.29b29f18.js
3362.4b0ac9dc.css
```

触发栈来自：

```text
bundler-runtime.3e21b29b.js
  -> __webpack_require__.l
  -> __webpack_require__.f.j
```

代表性时间线：

```text
DOM 1.36s -> chunks start 3.28s -> finish 4.33s -> load 4.57s
DOM 1.40s -> chunks start 4.60s -> finish 5.54s -> load 5.90s
DOM 1.77s -> chunks start 5.17s -> finish 5.41s -> load 5.67s
```

因此大部分等待不是这些资源“下载了几秒”，而是页面前端在 DOMContentLoaded 后又过了数秒才发起它们。

### Puppeteer completion 条件

`chrome-devtools-mcp 1.8.0` 的实际安装代码调用：

```text
page.pptrPage.goto(request.params.url, { timeout })
```

没有设置 `waitUntil`。同一 bundle 中 Puppeteer 的默认值是：

```text
waitUntil = ['load']
```

所以链路是：

```text
主文档快速返回
-> DOMContentLoaded
-> XHS 延迟动态加载 webpack chunks
-> window.load 被推迟
-> Puppeteer goto 默认持续等待 load
-> 尾延迟超过 10/15s 时抛 Navigation timeout
```

### 资源压力是放大器

与真实 timeout 同一故障窗口（09:00–09:10）的 `sysstat` 历史样本显示，这台 2 CPU / 约 2 GiB RAM 的 VM 出现严重本地 I/O 与换页压力：

```text
CPU iowait:       52.91%
loadavg-5:        11.93
loadavg-15:       15.24
vda queue aqu-sz: 54.22
vda await:        35.77 ms
swap-in:          734.44 pages/s
swap-out:         874.38 pages/s
major faults:     741.76/s
```

同一窗口网络接口只有几十 KiB/s 量级，并不存在链路带宽打满。更关键的是，当时连本机 `127.0.0.1:9222/json/version` 都曾在 3 秒内无响应；重启 Chrome 后立即恢复。因此外部 XHS 网络不能单独解释故障，Chrome/主机本地 I/O stall 是真实 timeout 的关键放大器。

故障后的资源检查还观察到：Chrome 相关进程 RSS 合计约 1.1 GiB，整机 Swap 驻留约 1.05 GiB。仅重启专用 Chrome、保持 persistent profile 不变，就使 Swap 驻留下降到约 338 MiB；登录态仍然保留。

同 URL、cache disabled 的 5 次 CDP 对照：

```text
重启前：load mean 8.755s, max 11.767s
重启后：load mean 6.918s, max  9.416s
```

主文档 TTFB 两组仍然只有约 0.15–0.27 秒量级。因此资源压力不是 XHS 晚发 chunk 的来源，但会明显放大 `window.load` 尾延迟，并最终把固定 10/15 秒预算推过阈值。

### `--disable-dev-shm-usage` A/B

目标机 `/dev/shm` 是约 984 MiB 的健康 tmpfs；旧 deployment 却强制使用 `--disable-dev-shm-usage`。实机观察中：

- 有 flag：`/dev/shm` 使用量为 0；
- 移除 flag：Chrome 正常启动并实际使用约 14–30 MiB `/dev/shm`；
- `/tmp` 没有独立 tmpfs mount，因此 fallback 落在根文件系统路径上。

用相同 XHS note、相同 raw-CDP 脚本、cache disabled 做 A1 → B → A2 crossover：

```text
A1 — with --disable-dev-shm-usage:
  5 runs, load mean 6.918s, max 9.416s

B  — without --disable-dev-shm-usage:
  5 runs, load mean 6.409s, max 6.751s

A2 — flag restored:
  5 runs, load mean 6.891s, max 7.878s
```

A1 与 A2 基本一致，B 组的平均值和尾部都更低。B 组 1 秒采样中的 swap-in 也低于两个 A 组，但 swap-out 仍然存在，因此不能把该 flag 当成全部内存压力的根因。

结论：这个 flag 不是 XHS 晚发 chunk 的 primary cause；在当前拥有充足 `/dev/shm`、同时又存在 Swap/I/O 压力的裸机上，它是没有必要的 deployment amplifier，应移除。

## 最终根因模型

以下结论来自：真实 timeout 同窗 sysstat、localhost false-negative reproduction、真实 XHS raw-CDP lifecycle 采样以及 A/B/crossover。原始 15 秒失败那一次没有提前挂载事件级 CDP recorder，因此这里区分“已直接观察的机制”与“由同窗证据支持的放大链路”。

1. **Primary mechanism**：`navigate_page` 继承 Puppeteer 的 `waitUntil=load`，而 XHS 在 DOMContentLoaded 后仍延迟动态加载会参与 `load` 的 webpack chunks。
2. **Host amplifier**：2 GiB 主机出现 Swap/major-fault/I/O pressure 时，页面生命周期与资源调度尾延迟进一步放大。
3. **Deployment amplifier**：在拥有约 984 MiB `/dev/shm` 的机器上仍使用 `--disable-dev-shm-usage`，把 Chrome shared-memory 路径不必要地转成 filesystem fallback。
4. **Not root cause**：Secure MCP Tunnel / Gateway；它们不是复现该页面生命周期现象的必要条件。

## 容量与运行治理结论

本次故障证明当前 **2 GiB RAM + 多个 MCP/runtime 共置** 不能视为有余量的生产级容量：它能够工作，但在 Chrome 多页面/renderer 累积后已经出现过持续 swap thrashing。当前不把某个 RAM 数值写成硬性安装门槛，因为尚未做不同内存规格的容量曲线测试；部署上应优先选择以下任一方式：

- 给 Source Acquisition Runtime 增加物理内存余量（4 GiB 可作为当前运维建议值，但不是经过容量测试证明的最小值）；或
- 将浏览器 Runtime 与其它重型 MCP/worker 隔离到不同主机；并且
- 每次 acquisition 结束后关闭由该次任务创建的 transient page，避免页面/renderer 无界累积；human takeover 正在使用的页面不得被自动清理。

`doctor --resource-pressure` 用于发现压力，不负责自动 kill Chrome/page，也不通过修改 swappiness 掩盖真实 working-set 不足。

## 部署修复

- 从 `source-chrome.service` 移除 `--disable-dev-shm-usage`；
- `deploy/chrome/install.sh` 要求 `/dev/shm` 是 tmpfs；可用空间低于 256 MiB 时 WARN；
- `doctor` 强制检查 live Chrome 使用原生 `/dev/shm`，防止磁盘 fallback 被重新引入；
- `doctor --resource-pressure` 额外检查 `MemAvailable`、Swap 使用量和 1 秒 active paging；Pilot 阈值只产生 WARN，不把瞬时资源压力误判成基础设施故障；
- 保留 `navigate_page` timeout 后核对 final URL 的 compatibility patch，作为防止危险重复操作的 safety net。

这两层不能互相替代：部署层减少 timeout 发生概率，兼容层保证 timeout 发生时上层不会把已执行动作误判为未执行。`window.load` 也不等于 Source readiness；Source capture 仍必须验证目标 URL、页面结构和实际 Source 内容。
