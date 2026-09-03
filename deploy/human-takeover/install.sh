#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! systemctl is-active --quiet source-xvfb.service; then
  echo "ERROR: source-xvfb.service must be active before installing human takeover" >&2
  exit 1
fi

DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends x11vnc novnc websockify

install -m 0644 "$script_dir/source-x11vnc.service" /etc/systemd/system/source-x11vnc.service
install -m 0755 "$script_dir/source-novnc" /usr/local/bin/source-novnc
install -m 0644 "$script_dir/source-novnc.service" /etc/systemd/system/source-novnc.service
install -m 0755 "$script_dir/start.sh" /usr/local/bin/source-human-takeover-start
install -m 0755 "$script_dir/stop.sh" /usr/local/bin/source-human-takeover-stop

systemctl daemon-reload
# Human takeover is intentionally temporary. Migrate older installs that enabled it.
systemctl disable --now source-novnc.service source-x11vnc.service >/dev/null 2>&1 || true
systemctl reset-failed source-novnc.service source-x11vnc.service >/dev/null 2>&1 || true

echo "Human takeover installed but inactive by default."
echo "Access-control boundary: authenticated Tailnet membership."
echo "VNC backend when started: loopback-only :5900"
echo "noVNC frontend when started: tailscale0 only :6080"
echo "Start only when human login is required: source-human-takeover-start"
echo "Stop immediately after human login: source-human-takeover-stop"
