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

## 3. 当前人工 Gate

用户需要在同一 Tailscale tailnet 的设备上打开：

```text
http://100.109.226.71:6080/vnc.html?autoconnect=1&resize=scale
```

然后在可视 Chrome 中按小红书正常流程完成登录。

完成后 Agent 必须重新读取页面状态，并验证 Chrome 重启后的登录态持久性。
