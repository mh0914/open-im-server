#!/usr/bin/env bash
set -u

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

print_line() {
  printf '%s\n' "------------------------------------------------------------"
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[PASS] %s\n' "$*"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf '[WARN] %s\n' "$*"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[FAIL] %s\n' "$*"
}

section() {
  print_line
  printf '[CHECK] %s\n' "$*"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

check_http_head() {
  local url="$1"
  local name="$2"

  if ! have_cmd curl; then
    fail "curl not found, cannot test $name"
    return
  fi

  if curl -k -I -L --connect-timeout 8 --max-time 20 -sS "$url" >/dev/null; then
    pass "$name reachable: $url"
  else
    warn "$name unreachable: $url"
  fi
}

check_pkg_available() {
  local pkg="$1"
  local label="$2"

  if dnf -q list --available "$pkg" >/dev/null 2>&1; then
    pass "$label available from dnf repo: $pkg"
    return 0
  fi

  if dnf -q info "$pkg" >/dev/null 2>&1; then
    pass "$label available from dnf repo: $pkg"
    return 0
  fi

  warn "$label not found in current dnf repo: $pkg"
  return 1
}

section "System"
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  printf 'NAME=%s\n' "${NAME:-unknown}"
  printf 'VERSION=%s\n' "${VERSION:-unknown}"
  printf 'ID=%s\n' "${ID:-unknown}"
else
  warn "/etc/os-release not found"
fi

printf 'Kernel: %s\n' "$(uname -a)"
printf 'Arch: %s\n' "$(uname -m)"

if [[ "$(uname -m)" == "x86_64" ]]; then
  pass "architecture is x86_64"
else
  fail "architecture is not x86_64"
fi

if have_cmd systemctl; then
  pass "systemd available: $(systemctl --version | head -n 1)"
else
  fail "systemctl not found"
fi

section "Disk and Memory"
df -h / /mnt /mnt/im 2>/dev/null || df -h /
free -h || true

ROOT_AVAIL_GB="$(df -BG / | awk 'NR==2 {gsub(/G/, "", $4); print $4}')"
if [[ -n "${ROOT_AVAIL_GB:-}" ]] && [[ "$ROOT_AVAIL_GB" -ge 20 ]]; then
  pass "root filesystem free space >= 20G"
else
  warn "root filesystem free space may be insufficient (<20G)"
fi

if df -BG /mnt/im >/dev/null 2>&1; then
  MNT_IM_AVAIL_GB="$(df -BG /mnt/im | awk 'NR==2 {gsub(/G/, "", $4); print $4}')"
  if [[ -n "${MNT_IM_AVAIL_GB:-}" ]] && [[ "$MNT_IM_AVAIL_GB" -ge 10 ]]; then
    pass "/mnt/im free space >= 10G"
  else
    warn "/mnt/im free space may be insufficient (<10G)"
  fi
else
  warn "/mnt/im not mounted yet"
fi

MEM_TOTAL_GB="$(free -g 2>/dev/null | awk '/^Mem:/ {print $2}')"
if [[ -n "${MEM_TOTAL_GB:-}" ]] && [[ "$MEM_TOTAL_GB" -ge 8 ]]; then
  pass "memory >= 8G"
else
  warn "memory < 8G, OpenIM may still run but capacity will be limited"
fi

section "Package Manager"
if have_cmd dnf; then
  pass "dnf found: $(command -v dnf)"
else
  fail "dnf not found"
fi

if dnf -q repolist >/dev/null 2>&1; then
  pass "dnf repo metadata readable"
else
  warn "dnf repolist failed"
fi

if dnf -q makecache >/dev/null 2>&1; then
  pass "dnf makecache succeeded"
else
  warn "dnf makecache failed"
fi

section "Network Reachability"
check_http_head "https://www.baidu.com" "general internet"
check_http_head "https://mirrors.aliyun.com" "common China mirror"
check_http_head "https://get.docker.com" "Docker installer site"
check_http_head "https://github.com" "GitHub"

section "Package Availability"
NGINX_OK=0
DOCKER_OK=0
COMPOSE_OK=0

if check_pkg_available "nginx" "nginx"; then
  NGINX_OK=1
fi

if check_pkg_available "docker" "docker engine"; then
  DOCKER_OK=1
elif check_pkg_available "docker-engine" "docker engine"; then
  DOCKER_OK=1
elif check_pkg_available "moby-engine" "docker engine"; then
  DOCKER_OK=1
fi

if check_pkg_available "docker-compose-plugin" "docker compose plugin"; then
  COMPOSE_OK=1
elif check_pkg_available "docker-compose" "docker compose"; then
  COMPOSE_OK=1
elif have_cmd docker && docker compose version >/dev/null 2>&1; then
  COMPOSE_OK=1
  pass "docker compose already installed"
fi

section "Port Occupancy"
if have_cmd ss; then
  ss -lntp | egrep ':(80|443|10001|10002|10004|10005|10008|10009)\b' || true
  if ss -lntp | egrep ':(80|443|10001|10002|10004|10005|10008|10009)\b' >/dev/null 2>&1; then
    warn "one or more target ports are already in use"
  else
    pass "target ports are currently free"
  fi
else
  warn "ss command not found, port check skipped"
fi

section "Result"
printf 'PASS=%s WARN=%s FAIL=%s\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  printf '\nConclusion: server is not ready yet. Fix FAIL items first.\n'
  exit 1
fi

if [[ "$DOCKER_OK" -eq 1 && "$NGINX_OK" -eq 1 ]]; then
  if [[ "$COMPOSE_OK" -eq 1 ]]; then
    printf '\nConclusion: server supports direct deployment with dnf packages.\n'
  else
    printf '\nConclusion: server can deploy, but docker compose should be provided locally.\n'
  fi
else
  printf '\nConclusion: prepare offline installers before deployment.\n'
  printf 'Recommended local uploads:\n'
  printf '  /mnt/im/installers/get-docker.sh\n'
  printf '  /mnt/im/installers/docker-compose-linux-x86_64\n'
  printf '  /mnt/im/rpms/*.rpm\n'
fi
