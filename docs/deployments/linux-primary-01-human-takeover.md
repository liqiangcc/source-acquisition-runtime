# linux-primary-01 人工接管补充记录

## 1. 触发原因

2026-09-03，在本机 Gate A-D 全部通过后，通过真实 Chrome DevTools MCP 打开：

```text
https://www.xiaohongshu.com/
```

页面正常到达：

```text
https://www.xiaohongshu.com/explore
```

MCP snapshot 明确显示登录遮罩，并提供扫码与手机号登录入口。

分类：

```text
XHS normal page reachable: PASS
site session: manual-login-required
```

没有尝试绕过登录或平台验证。

## 2. 实际部署

真实需求出现后才安装：

- x11vnc 0.9.16
- noVNC 1.3.0
- websockify 0.10.0

服务：

```text
source-x11vnc.service: active
source-novnc.service: active
```

实际监听：

```text
127.0.0.1:5900
[::1]:5900
100.109.226.71:6080
```

noVNC `6080` 在以下地址不可达：

```text
127.0.0.1
192.168.119.10
28.0.0.1
```

Tailscale 地址 `100.109.226.71:6080` 的 noVNC 页面实际 HTTP smoke PASS。

Chrome CDP 在增加 human takeover 后仍然只监听：

```text
127.0.0.1:9222
```

因此人工接管没有改变 CDP 安全边界，也没有启动 Remote MCP / Gateway / Tunnel。

## 3. 人工 Gate（已完成）

用户在同一 Tailscale tailnet 的设备上打开：

```text
http://100.109.226.71:6080/vnc.html?autoconnect=1&resize=scale
```

然后在可视 Chrome 中按小红书正常流程完成登录。

2026-09-03 用户完成正常登录。

## 4. 登录态与 Profile 持久性验证

人工登录完成后，Chrome DevTools MCP 实际读取到两个小红书标签页：一个旧标签仍保留登录弹窗，另一个已进入真实账号态。已登录页面满足：

```text
login prompt: absent
account navigation: 通知 / 消息 / 我
profile link: present
```

因此没有把“用户说已登录”直接当成成功，而是以浏览器实际页面状态确认。

随后执行：

```text
stop + disable source-novnc.service / source-x11vnc.service
restart source-chrome.service
open a fresh https://www.xiaohongshu.com/explore via Chrome DevTools MCP
```

真实结果：

```text
Chrome PID: 304268 -> 311036
Browser Profile inode: 2474 -> 2474
Browser Profile owner/mode: source-runtime:source-runtime 700
CDP listener: 127.0.0.1:9222 only
5900/6080 listeners after takeover stop: none
fresh page login_prompt=false
fresh page account_navigation=true
login_persistence=PASS
```

这证明首个真实站点登录态能够跨 Chrome service restart 由同一个 dedicated Browser Profile 持久化。没有读取、记录或提交 Cookie、Token 或 Profile 内容。

## 5. Human-takeover 生命周期修正

真实 Pilot 证明人工接管只是登录期间的短暂能力，不应成为常驻服务。因此实现调整为：

```text
install -> inactive by default
source-human-takeover-start -> temporary 5900/6080
human login
source-human-takeover-stop -> no 5900/6080 listeners
core Chrome/Xvfb/CDP/MCP continue running
```

默认 `scripts/doctor` 不再要求 human-takeover active；只有显式 `--human-takeover` 才验证该临时层。
