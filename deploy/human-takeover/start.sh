#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

if ! systemctl is-active --quiet source-xvfb.service; then
  echo "ERROR: source-xvfb.service must be active" >&2
  exit 1
fi

if ! systemctl is-active --quiet source-chrome.service; then
  echo "ERROR: source-chrome.service must be active" >&2
  exit 1
fi

takeover_ip="$(ip -4 -o addr show dev tailscale0 scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)"
if [[ -z "$takeover_ip" ]]; then
  echo "ERROR: tailscale0 has no IPv4 address" >&2
  exit 1
fi

systemctl start source-x11vnc.service source-novnc.service
systemctl is-active --quiet source-x11vnc.service
systemctl is-active --quiet source-novnc.service

echo "Human takeover active."
echo "Open from a device in the same tailnet: http://${takeover_ip}:6080/vnc.html?autoconnect=1&resize=scale"
echo "After login completes: source-human-takeover-stop"
