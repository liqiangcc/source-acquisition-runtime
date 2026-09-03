#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

source /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *) echo "ERROR: unsupported distribution: ${ID:-unknown}" >&2; exit 1 ;;
esac

arch="$(dpkg --print-architecture)"
if [[ "$arch" != "amd64" ]]; then
  echo "ERROR: first pilot supports amd64 only; got $arch" >&2
  exit 1
fi

free_kb="$(df --output=avail / | tail -1 | tr -d ' ')"
if (( free_kb < 3145728 )); then
  echo "ERROR: require at least 3 GiB free on / before Chrome installation" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg xvfb

install -d -m 0755 /usr/share/keyrings
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor --yes -o /usr/share/keyrings/google-chrome.gpg
chmod 0644 /usr/share/keyrings/google-chrome.gpg
cat >/etc/apt/sources.list.d/google-chrome.list <<'EOF'
deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main
EOF

apt-get update
apt-get install -y --no-install-recommends google-chrome-stable

if ! id source-runtime >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/source-acquisition-runtime --create-home --shell /usr/sbin/nologin source-runtime
fi

install -d -o source-runtime -g source-runtime -m 0700 \
  /var/lib/source-acquisition-runtime \
  /var/lib/source-acquisition-runtime/chrome-profile \
  /var/lib/source-acquisition-runtime/state
install -d -o source-runtime -g source-runtime -m 0750 \
  /var/lib/source-acquisition-runtime/artifacts \
  /var/log/source-acquisition-runtime
install -d -o root -g source-runtime -m 0750 /etc/source-acquisition-runtime
install -d -o root -g root -m 0755 /opt/source-acquisition-runtime

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
install -m 0644 "$script_dir/source-xvfb.service" /etc/systemd/system/source-xvfb.service
install -m 0644 "$script_dir/source-chrome.service" /etc/systemd/system/source-chrome.service

systemctl daemon-reload
systemctl enable --now source-xvfb.service
systemctl enable --now source-chrome.service

for _ in $(seq 1 30); do
  if curl -fsS --max-time 1 http://127.0.0.1:9222/json/version >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS --max-time 2 http://127.0.0.1:9222/json/version >/dev/null; then
  echo "ERROR: Chrome started but localhost CDP is not reachable" >&2
  systemctl --no-pager --full status source-chrome.service >&2 || true
  exit 1
fi

bad_bind="$(ss -H -ltn 'sport = :9222' | awk '{print $4}' | grep -Ev '^(127\.0\.0\.1|\[::1\]):9222$' || true)"
if [[ -n "$bad_bind" ]]; then
  echo "ERROR: CDP has a non-loopback listener:" >&2
  printf '%s\n' "$bad_bind" >&2
  exit 1
fi

printf 'Chrome: %s\n' "$(google-chrome-stable --version)"
printf 'CDP: localhost-only on 127.0.0.1:9222\n'
printf 'Profile: /var/lib/source-acquisition-runtime/chrome-profile\n'
