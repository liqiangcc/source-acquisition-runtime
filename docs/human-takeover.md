# 人工接管边界

## 1. 何时启用

人工接管不是默认部署层。只有真实网站已经证明需要正常人工登录、扫码、验证码确认或页面视觉调试时才启用。

首个 `linux-primary-01` Pilot 中，小红书首页通过 Chrome DevTools MCP 正常到达 `https://www.xiaohongshu.com/explore`，页面明确显示登录遮罩与扫码/手机号登录，因此进入：

```text
manual-login-required
```

这时才增加本文件定义的 human-takeover 层。

## 2. 拓扑

```text
人工设备（同一 Tailscale tailnet）
        ↓
Tailscale interface :6080
        ↓
noVNC / websockify
        ↓
127.0.0.1:5900
        ↓
x11vnc
        ↓
Xvfb :99
        ↓
同一 persistent Chrome
```

这条链路只用于人工查看/操作已经运行的专用浏览器，不是 Remote MCP transport。

## 3. 安全边界

当前实现要求：

- x11vnc 只监听 loopback `5900`；
- noVNC 只绑定 `tailscale0` 的 IPv4 `6080`；
- eth0、Mihomo、localhost 不监听 noVNC `6080`；
- Chrome CDP 继续只监听 `127.0.0.1:9222`；
- 不把 VNC/noVNC 当作 MCP Gateway；
- 不把 `:9222` 接到 noVNC、Tailscale Serve、Tunnel 或公网反向代理。

`x11vnc` 使用 `-nopw`，因为 RFB 端口本身只存在于 loopback；网络访问控制由 noVNC 的 tailnet-only bind 提供。**如果未来不再使用受控 tailnet 边界，必须重新设计认证，不能把无密码 VNC/noVNC 暴露到普通 LAN 或公网。**

## 4. 安装

前提：

- `source-xvfb.service` 已 active；
- `source-chrome.service` 已使用同一个 dedicated profile；
- 主机已经加入目标 Tailscale tailnet。

执行：

```text
deploy/human-takeover/install.sh
```

安装：

- `x11vnc`
- `novnc`
- `websockify`
- `source-x11vnc.service`
- `source-novnc.service`

默认：

```text
SOURCE_TAKEOVER_INTERFACE=tailscale0
SOURCE_TAKEOVER_PORT=6080
```

## 5. 验收

至少证明：

```text
source-xvfb.service active
source-chrome.service active
source-x11vnc.service active
source-novnc.service active
127.0.0.1:5900 reachable only locally
<Tailscale IPv4>:6080 reachable
eth0:6080 not reachable
Mihomo interface:6080 not reachable
Chrome CDP still 127.0.0.1:9222 only
```

人工接管完成后，Agent 必须重新读取当前 URL/page identity，不能沿用接管前页面假设。

## 6. 登录规则

人工接管允许用户正常完成：

- 平台扫码登录；
- 手机号/平台正常认证；
- 平台要求的人工确认。

不允许 Runtime 自动绕过验证码、设备确认或平台安全机制。

完成登录后关闭或保留 human-takeover service 都不应改变 Browser Profile identity；随后应验证：

```text
正常登录
→ Agent 重新读取页面状态
→ Chrome restart
→ same dedicated profile
→ 正常会话按浏览器/平台自身规则仍可用
```
