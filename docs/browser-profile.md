# Browser Profile 与登录态

## 1. 目的

需要登录的网站要求浏览器状态跨 Agent 会话持续存在。

因此 Browser Profile 是 Runtime 的持久状态，不是某次 MCP 调用的临时目录。

```text
Agent session A ─┐
Agent session B ─┼→ Chrome DevTools MCP → same dedicated Chrome profile
Manual operator ─┘
```

## 2. 使用独立 Profile

采集浏览器必须使用专用 user data directory，例如：

```text
/var/lib/source-acquisition-runtime/chrome-profile
```

不得直接复用个人日常 Chrome 默认 Profile。

原因：

- Remote debugging 可以操作该 Profile 中打开的页面；
- 采集环境需要可独立备份、重置和诊断；
- 站点登录态应该和个人浏览数据分离；
- Chrome 当前对 remote debugging 也要求使用非默认 user data directory。

## 3. Profile 中包含什么

Profile 可能包含：

```text
Cookie
LocalStorage
IndexedDB
site preferences
session state
browser cache
other Chrome profile state
```

因此它属于运行时敏感状态。

规则：

- 不提交 Git；
- 不写入普通调试日志；
- 目录权限只允许 runtime 用户访问；
- Artifact 导出不复制整个 Profile；
- 需要迁移时采用独立受控流程。

## 4. 登录流程

首次登录推荐人工完成：

```text
启动专用 Chrome
↓
通过本机/受控远程桌面查看浏览器
↓
用户正常完成登录
↓
确认目标网站可访问
↓
关闭人工控制面
↓
Agent 继续复用同一 Profile
```

Skill 的职责不是自动生成认证状态。

当站点要求用户重新确认身份时，Runtime 应报告：

```text
site-session-expired
manual-login-required
```

而不是把它误判成 DOM 解析故障。

## 5. 为什么 Chrome 与 MCP 生命周期分开

推荐：

```text
persistent Chrome process
        ↑
        │ CDP
replaceable MCP process
```

这样：

- MCP 升级不重建 Profile；
- MCP crash 不自然丢登录态；
- Agent 会话结束不关闭浏览器状态；
- 人工调试与 Agent 可以在明确控制下使用同一个专用浏览器。

## 6. 并发规则

首个 Pilot：

```text
1 runtime
1 Chrome profile
1 active acquisition flow
```

暂不允许多个 Agent 同时随意操作同一 Profile。

因为共享浏览器并发会产生：

- tab identity 混淆；
- navigation 相互覆盖；
- 当前页面错配；
- Source capture provenance 难以证明。

如果未来需要并发，应显式引入：

```text
session identity
page ownership
profile isolation
concurrency gate
```

而不是默认“Chrome 能开很多 tab 所以并发安全”。

## 7. 人工接管

对于真实网站，人工接管是正常 runtime 能力，不是异常 workaround。

推荐支持：

```text
Xvfb / desktop session
+
受控 noVNC 或其他远程桌面
```

使用场景：

- 初始登录；
- 登录状态确认；
- 页面发生重大变化；
- 需要验证 Agent 看到的页面是否和真实浏览器一致。

人工接管完成后，Agent 必须重新获取当前 page state，不能继续使用接管前的页面假设。

## 8. Profile Reset

需要重置的典型情况：

- Profile 损坏；
- 专用账号退出使用；
- 环境重新初始化；
- 测试要求全新会话。

重置流程必须显式执行：

```text
stop Chrome
↓
archive or remove old dedicated profile
↓
create clean profile
↓
start Chrome
↓
manual login
↓
run smoke test
```

不要在普通 `restart` 中自动删除 Profile。

## 9. Artifact 与 Profile 分离

Source Artifact 只保存与目标来源有关的证据：

```text
URL
HTML/page capture
source images
metadata
hash
limitations
```

不能为了“保存证据”把整份 Browser Profile 当作 Source Artifact。

Browser Profile = runtime state。

Source Artifact = 可审计的采集输出。

这是必须保持的边界。

## 10. 验收条件

首个部署至少证明：

1. 重启 Chrome DevTools MCP 后登录态保持；
2. 重启 Gateway/Tunnel 后登录态保持；
3. 服务器重启并重新启动 Chrome 后，正常持久会话按浏览器自身规则恢复；
4. `git status` 不会出现 Browser Profile 文件；
5. 人工可以查看并恢复登录状态；
6. Agent 能明确区分“页面失败”和“需要人工登录”。