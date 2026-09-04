#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

for cmd in node npm; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing $cmd" >&2; exit 1; }
done

node - <<'NODE'
const [major, minor] = process.versions.node.split('.').map(Number);
const ok = (major === 20 && minor >= 19) || (major === 22 && minor >= 12) || major >= 23;
if (!ok) {
  console.error(`ERROR: unsupported Node.js ${process.versions.node}; chrome-devtools-mcp 1.8.0 requires ^20.19.0 || ^22.12.0 || >=23`);
  process.exit(1);
}
NODE

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
# shellcheck disable=SC1091
source "$script_dir/version.env"

mcp_root=/opt/source-acquisition-runtime/chrome-devtools-mcp
install -d -o root -g root -m 0755 "$mcp_root"
cat >"$mcp_root/package.json" <<EOF
{
  "name": "source-acquisition-runtime-chrome-devtools-mcp",
  "private": true,
  "dependencies": {
    "chrome-devtools-mcp": "${CHROME_DEVTOOLS_MCP_VERSION}",
    "@modelcontextprotocol/sdk": "${MCP_SDK_VERSION}"
  }
}
EOF

# The runtime owns the persistent system Chrome lifecycle. Prevent Puppeteer,
# a dependency of chrome-devtools-mcp, from downloading a second browser.
PUPPETEER_SKIP_DOWNLOAD=true npm install --prefix "$mcp_root" --omit=dev --no-audit --no-fund

actual="$(node -p "require('$mcp_root/node_modules/chrome-devtools-mcp/package.json').version")"
if [[ "$actual" != "$CHROME_DEVTOOLS_MCP_VERSION" ]]; then
  echo "ERROR: expected chrome-devtools-mcp $CHROME_DEVTOOLS_MCP_VERSION, installed $actual" >&2
  exit 1
fi

node "$script_dir/apply-compat-patches.mjs" "$mcp_root"

install -m 0755 "$script_dir/source-chrome-devtools-mcp" /usr/local/bin/source-chrome-devtools-mcp
install -m 0755 "$repo_root/scripts/mcp-smoke.mjs" "$mcp_root/mcp-smoke.mjs"

printf 'chrome-devtools-mcp: %s (pinned)\n' "$actual"
printf 'wrapper: /usr/local/bin/source-chrome-devtools-mcp\n'
