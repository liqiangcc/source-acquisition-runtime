#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/version.env"

case "$(uname -m)" in
  x86_64|amd64) arch=linux_amd64 ;;
  *) echo "ERROR: unsupported architecture for first gateway Pilot: $(uname -m)" >&2; exit 1 ;;
esac

install_root=/opt/source-acquisition-runtime/gateway
config_root=/etc/source-acquisition-runtime
url="https://github.com/TBXark/mcp-proxy/releases/download/v${MCP_PROXY_VERSION}/mcp-proxy_${MCP_PROXY_VERSION}_${arch}.tar.gz"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -fL --connect-timeout 10 --max-time 120 "$url" -o "$work/mcp-proxy.tar.gz"
actual="$(sha256sum "$work/mcp-proxy.tar.gz" | awk '{print $1}')"
if [[ "$actual" != "$MCP_PROXY_LINUX_AMD64_SHA256" ]]; then
  echo "ERROR: mcp-proxy checksum mismatch" >&2
  echo "expected=$MCP_PROXY_LINUX_AMD64_SHA256" >&2
  echo "actual=$actual" >&2
  exit 1
fi

tar -xzf "$work/mcp-proxy.tar.gz" -C "$work"
test -x "$work/mcp-proxy"

install -d -m 0755 "$install_root" "$config_root"
install -m 0755 "$work/mcp-proxy" "$install_root/mcp-proxy"
install -m 0644 "$script_dir/gateway.json" "$config_root/gateway.json"
install -m 0644 "$script_dir/source-mcp-gateway.service" /etc/systemd/system/source-mcp-gateway.service

"$install_root/mcp-proxy" -config "$config_root/gateway.json" -check-config

systemctl daemon-reload
systemctl enable --now source-mcp-gateway.service

for _ in $(seq 1 30); do
  if curl -fsS --max-time 1 "http://127.0.0.1:${MCP_PROXY_PORT}/_readyz" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -fsS --max-time 2 "http://127.0.0.1:${MCP_PROXY_PORT}/_healthz" >/dev/null
curl -fsS --max-time 2 "http://127.0.0.1:${MCP_PROXY_PORT}/_readyz" >/dev/null

echo "MCP gateway installed."
echo "Gateway: http://127.0.0.1:${MCP_PROXY_PORT}/chrome-devtools/mcp"
echo "Health:  http://127.0.0.1:${MCP_PROXY_PORT}/_healthz"
echo "CDP remains local-only at http://127.0.0.1:9222"
