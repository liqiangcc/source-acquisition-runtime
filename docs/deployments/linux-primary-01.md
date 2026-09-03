# linux-primary-01 部署记录

## 1. 记录范围

本文件记录 `source-acquisition-runtime` 首个真实 Linux Deployment Target 的**非敏感环境事实、部署结果、失败证据与 Gate 验收**。

- Deployment identity：`linux-primary-01`
- Pilot date：2026-09-03
- Target hostname：`ecs-node`
- 目标：先验证本机 `Chrome → localhost CDP → Chrome DevTools MCP → 浏览器实际操作`，Remote MCP / Gateway / Tunnel 后置。

本文件不记录密码、Cookie、Session token、SSH 私钥、Tunnel secret、API key、代理凭据或 Browser Profile 内容。

## 2. 主机事实

| 项目 | 实际值 |
| --- | --- |
| Distribution | Ubuntu 24.04.4 LTS |
| Architecture | x86_64 |
| Kernel | 6.8.0-106-generic |
| CPU | Intel Xeon Platinum 8336C，2 vCPU |
| Memory | 约 1.9 GiB |
| Init | systemd |
| Runtime user used for deployment | root |
| Browser runtime user | `source-runtime` |
| Node.js | v22.23.2 |
| npm / npx | 10.9.8 |
| Docker | absent |
| Tailscale | 1.102.3，online |
| cloudflared | 2026.7.2，service inactive |
| Existing host proxy/TUN | Mihomo process/interface present |
| HTTP_PROXY / HTTPS_PROXY / ALL_PROXY / NO_PROXY | unset at probe time |

网络接口探测时包括：

- `eth0`: `192.168.119.10/16`
- `tailscale0`: `100.109.226.71/32`
- Mihomo interface: `28.0.0.1/30`

这些是部署时环境事实，不表示 Runtime 对这些地址建立远程入口。

## 3. 磁盘阻塞与处理

初始根分区约：

```text
40G total / 37G used / 944M free / 98%
```

直接安装 Chrome 风险过高。只读盘点发现主要空间来自已完成的其他 Rust worktree 可重建构建产物：

```text
/root/reading-mcp-issue-54/target  ~13G
/root/reading-mcp-issue-53/target  ~4.1G
```

删除前确认：

1. 两个 worktree `git status --short` 均为空；
2. 没有 cargo/rustc/test 进程引用这两个 worktree；
3. `target/` 不是 mountpoint；
4. 不删除源码、`.git`、配置或凭据。

随后仅删除上述两个 `target/`，并将 systemd journal vacuum 到 100M。`/root/reading-mcp/target` 未处理。

处理后根分区约：

```text
40G total / 20G used / 18G free / 53%
```

Chrome/MCP 完成安装后的根分区约仍有 17G 可用。

## 4. Browser Runtime

实际安装：

```text
Google Chrome 152.0.7977.75
/usr/bin/google-chrome-stable
```

专用持久 Profile：

```text
/var/lib/source-acquisition-runtime/chrome-profile
owner: source-runtime:source-runtime
mode: 0700
```

Profile 已产生真实 Chrome runtime state，但 Profile 内容不进入 Git，也不作为 Source Artifact。

当前服务形态：

```text
source-xvfb.service
    ↓ DISPLAY=:99
source-chrome.service
    ↓
127.0.0.1:9222
```

Xvfb：

```text
/usr/bin/Xvfb :99 -screen 0 1280x960x24 -nolisten tcp -noreset
```

当前保留 Xvfb 是为了让同一专用 Profile 后续可以支持正常人工登录/调试。**noVNC 或其他远程桌面尚未部署**；只有真实人工接管需求出现后再增加。

Chrome 生命周期由 systemd 管理，不依赖一次 MCP 调用。

## 5. CDP 安全边界

实际监听：

```text
127.0.0.1:9222
```

`/json/version` 可读：

```text
Browser: Chrome/152.0.7977.75
Protocol-Version: 1.3
```

负向验证：以下地址的 `:9222` 均不可达：

```text
192.168.119.10:9222
100.109.226.71:9222
28.0.0.1:9222
```

同时未发现 X11 TCP listener；Xvfb 使用 `-nolisten tcp`。

因此当前边界满足：

```text
Chrome DevTools MCP → localhost CDP → Chrome
```

CDP 没有暴露到 eth0、Tailscale、Mihomo 或 Remote MCP/Tunnel。

## 6. Chrome DevTools MCP

Pilot 固定版本：

```text
chrome-devtools-mcp = 1.8.0
@modelcontextprotocol/sdk = 1.30.0
```

安装目录：

```text
/opt/source-acquisition-runtime/chrome-devtools-mcp
```

安装脚本设置：

```text
PUPPETEER_SKIP_DOWNLOAD=true
```

因此 MCP 使用已经由 Runtime 管理的系统 Chrome，不额外下载第二份浏览器。

连接方式：

```text
--browser-url=http://127.0.0.1:9222
```

## 7. Gate 验收

### Gate A — Chrome

**PASS**

- Chrome Stable 已安装；
- `source-chrome.service` active + enabled；
- 使用独立持久 Profile；
- 普通 HTTPS 页面 `https://example.com/` 可由同一 Chrome 正常打开。

### Gate B — localhost CDP

**PASS**

- `/json/version`、`/json/list` 可读；
- `9222` 只绑定 `127.0.0.1`；
- eth0 / Tailscale / Mihomo 地址均不能访问 `9222`。

### Gate C — Chrome DevTools MCP

**PASS**

- 固定 `chrome-devtools-mcp 1.8.0` 已安装；
- MCP 可以连接已经运行的系统 Chrome；
- tool discovery 实测得到 29 个工具。

### Gate D — 实际浏览器能力

**PASS**

真实 smoke 已完成：

```text
MCP tool discovery
→ list_pages
→ new_page https://example.com
→ take_snapshot
→ 读取 Example Domain 页面结构
→ 打开本地测试页面
→ evaluate_script 执行一次按钮交互
→ 再次 take_snapshot 验证交互结果
```

这证明部署成功不是只以“进程启动”判断。

## 8. 首次真实失败：pageId routing

第一次 MCP smoke 在工具枚举和 `list_pages` 成功后失败：

```text
Error: take_snapshot failed:
MCP error -32602: Input validation error:
Invalid arguments for tool take_snapshot: Required at pageId
```

Failure class：

```text
mcp-tool-error / smoke-client-incompatible-with-page-id-routing
```

原因：`chrome-devtools-mcp 1.8.0` 默认启用 pageId routing，page-scoped tool 必须显式提供 `pageId`。

修复策略不是关闭 pageId routing，而是让 smoke：

```text
new_page
→ list_pages 获取 selected pageId
→ take_snapshot(pageId)
→ evaluate_script(pageId)
```

修复提交：

```text
25337f8614107c0cd649654de8c0a14b5ef07c81
fix: route MCP smoke by explicit page id
```

修复后完整 smoke PASS。

## 9. 生命周期隔离验证

连续运行两次独立 MCP smoke：

```text
smoke #1 PASS
smoke #2 PASS
```

两次运行前后 Chrome MainPID 均保持：

```text
301621
```

MCP smoke 进程退出后没有要求 Chrome 退出，证明 MCP 生命周期与 Chrome 生命周期分离。

随后重启 `source-chrome.service`：

```text
Chrome MainPID: 301621 → 303184
```

重启后：

- `source-chrome.service` active；
- `source-xvfb.service` active；
- Profile 目录仍为同一路径，目录 inode 保持不变；
- owner/mode 仍为 `source-runtime:source-runtime / 0700`；
- CDP 恢复为 `127.0.0.1:9222`；
- `Chrome/152.0.7977.75` 可重新连接；
- 完整 MCP smoke 再次 PASS。

这证明了运行时 Profile 目录与 MCP/Chrome 进程生命周期解耦。**小红书登录态跨 Chrome 重启是否保持，必须在用户正常登录后另行验证，不能由本 smoke 推断。**

## 10. 当前未开始的 Gate

截至本记录：

- 未部署 noVNC / remote desktop；
- 未访问小红书；
- 未执行扫码、验证码或登录；
- 未启动 MCP Gateway；
- 未启动 Remote MCP / Secure MCP Tunnel；
- 未把 CDP 暴露为远程服务。

下一阶段应先验证小红书正常页面与登录状态需求；只有实际证明需要人工接管时，再增加受控可视入口。Remote MCP / Gateway / Tunnel 仍然必须终止在 MCP transport 层，而不是 `:9222`。
