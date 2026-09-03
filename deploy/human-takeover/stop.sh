#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

systemctl stop source-novnc.service source-x11vnc.service >/dev/null 2>&1 || true
systemctl reset-failed source-novnc.service source-x11vnc.service >/dev/null 2>&1 || true

listeners="$(ss -H -ltn | grep -E ':(5900|6080)\b' || true)"
if [[ -n "$listeners" ]]; then
  echo "ERROR: human-takeover listener remains after stop:" >&2
  printf '%s\n' "$listeners" >&2
  exit 1
fi

echo "Human takeover inactive; ports 5900/6080 have no listeners."
