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
