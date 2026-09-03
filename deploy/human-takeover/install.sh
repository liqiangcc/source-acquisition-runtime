#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
state_dir=/var/lib/source-acquisition-runtime/state
password_file="$state_dir/x11vnc.pass"

if ! systemctl is-active --quiet source-xvfb.service; then
  echo "ERROR: source-xvfb.service must be active before installing human takeover" >&2
  exit 1
fi

if [[ ! -s "$password_file" ]]; then
  echo "ERROR: missing VNC password file: $password_file" >&2
  echo "Create it locally with x11vnc -storepasswd before enabling human takeover; never commit it to Git." >&2
  exit 1
fi

chown source-runtime:source-runtime "$password_file"
chmod 0600 "$password_file"

DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends x11vnc novnc websockify

install -m 0644 "$script_dir/source-x11vnc.service" /etc/systemd/system/source-x11vnc.service
install -m 0755 "$script_dir/source-novnc" /usr/local/bin/source-novnc
install -m 0644 "$script_dir/source-novnc.service" /etc/systemd/system/source-novnc.service

systemctl daemon-reload
systemctl enable --now source-x11vnc.service source-novnc.service

echo "Human takeover installed."
echo "VNC backend: password-protected, loopback-only :5900"
echo "noVNC frontend: tailnet interface only :6080"
echo "Open on a device in the same tailnet: http://$(tailscale ip -4 | head -1):6080/vnc.html?autoconnect=1&resize=scale"
