#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/mnt/im}"
DEPLOY_BUNDLE_NAME="${DEPLOY_BUNDLE_NAME:-openim-kylin2303-deploy-bundle-20260411.tar.gz}"
IMAGE_BUNDLE_NAME="${IMAGE_BUNDLE_NAME:-openim-kylin2303-images-20260411-amd64.tar.gz}"
DEPLOY_SHA_NAME="${DEPLOY_SHA_NAME:-${DEPLOY_BUNDLE_NAME}.sha256}"
IMAGE_SHA_NAME="${IMAGE_SHA_NAME:-${IMAGE_BUNDLE_NAME}.sha256}"
INSTALL_SCRIPT_NAME="${INSTALL_SCRIPT_NAME:-install-openim-kylin.sh}"
VERIFY_TIMEOUT_SECONDS="${VERIFY_TIMEOUT_SECONDS:-900}"
OPENIM_SECRET="${OPENIM_SECRET:-openIM123}"
ADMIN_USER_ID="${ADMIN_USER_ID:-imAdmin}"

log() {
  printf '[openim] %s\n' "$*"
}

die() {
  printf '[openim] ERROR: %s\n' "$*" >&2
  exit 1
}

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "please run this script as root"
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ensure_file() {
  local file="$1"
  [[ -f "$file" ]] || die "required file not found: $file"
}

verify_sha256_if_present() {
  local file="$1"
  local sha_file="$2"

  if [[ ! -f "$sha_file" ]]; then
    log "skip sha256 check because file is not present: $sha_file"
    return 0
  fi

  have_cmd sha256sum || die "sha256sum command not found"
  log "verify checksum: $(basename "$file")"
  (
    cd "$(dirname "$file")"
    sha256sum -c "$(basename "$sha_file")"
  )
}

prepare_files() {
  mkdir -p "$BASE_DIR/images"

  ensure_file "$BASE_DIR/$DEPLOY_BUNDLE_NAME"
  ensure_file "$BASE_DIR/$IMAGE_BUNDLE_NAME"

  verify_sha256_if_present "$BASE_DIR/$DEPLOY_BUNDLE_NAME" "$BASE_DIR/$DEPLOY_SHA_NAME"
  verify_sha256_if_present "$BASE_DIR/$IMAGE_BUNDLE_NAME" "$BASE_DIR/$IMAGE_SHA_NAME"

  log "extract deployment bundle to $BASE_DIR"
  tar -xzf "$BASE_DIR/$DEPLOY_BUNDLE_NAME" -C "$BASE_DIR"

  ensure_file "$BASE_DIR/$INSTALL_SCRIPT_NAME"

  log "place image bundle into $BASE_DIR/images"
  cp -f "$BASE_DIR/$IMAGE_BUNDLE_NAME" "$BASE_DIR/images/$IMAGE_BUNDLE_NAME"

  chmod +x "$BASE_DIR/$INSTALL_SCRIPT_NAME"
}

run_install() {
  log "start install script"
  bash "$BASE_DIR/$INSTALL_SCRIPT_NAME"
}

wait_for_running() {
  local container="$1"
  local timeout="$2"
  local start_ts now_ts state

  start_ts="$(date +%s)"
  while true; do
    if docker inspect "$container" >/dev/null 2>&1; then
      state="$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || true)"
      if [[ "$state" == "running" ]]; then
        log "container running: $container"
        return 0
      fi
    fi

    now_ts="$(date +%s)"
    if (( now_ts - start_ts >= timeout )); then
      docker ps -a || true
      die "container did not reach running state in time: $container"
    fi
    sleep 5
  done
}

wait_for_healthy() {
  local container="$1"
  local timeout="$2"
  local start_ts now_ts state health

  start_ts="$(date +%s)"
  while true; do
    if docker inspect "$container" >/dev/null 2>&1; then
      state="$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || true)"
      health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container" 2>/dev/null || true)"
      if [[ "$health" == "healthy" ]]; then
        log "container healthy: $container"
        return 0
      fi
      if [[ "$state" == "running" && -z "$health" ]]; then
        log "container running without healthcheck: $container"
        return 0
      fi
    fi

    now_ts="$(date +%s)"
    if (( now_ts - start_ts >= timeout )); then
      docker ps -a || true
      docker logs --tail 100 "$container" || true
      die "container did not become healthy in time: $container"
    fi
    sleep 5
  done
}

verify_nginx() {
  local body
  body="$(curl -fsS --max-time 20 http://127.0.0.1/ || true)"
  [[ "$body" == *"openim nginx ok"* ]] || die "nginx verification failed"
  log "nginx response verified"
}

verify_admin_token() {
  local op_id response

  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    op_id="$(cat /proc/sys/kernel/random/uuid)"
  else
    op_id="$(date +%s)"
  fi

  response="$(curl -fsS --max-time 30 \
    -X POST "http://127.0.0.1/api/auth/get_admin_token" \
    -H "Content-Type: application/json" \
    -H "operationID: ${op_id}" \
    -d "{\"secret\":\"${OPENIM_SECRET}\",\"userID\":\"${ADMIN_USER_ID}\"}")"

  printf '%s' "$response" | grep -Eq '"(errCode|code)"[[:space:]]*:[[:space:]]*0' || {
    printf '%s\n' "$response"
    die "failed to obtain admin token from openim api"
  }

  log "openim admin token api verified"
}

show_runtime_status() {
  printenv >/dev/null 2>&1 || true
  echo
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  echo
  log "public urls"
  echo "  Local Nginx: http://127.0.0.1/"
  echo "  API:         http://127.0.0.1/api"
  echo "  Chat:        http://127.0.0.1/chat"
  echo "  WebSocket:   ws://127.0.0.1/msg_gateway"
  echo "  MinIO:       http://127.0.0.1/minio"
  echo
  log "if SLB mapping is already configured, Internet URLs are"
  echo "  API:         http://59.46.214.114:18080/api"
  echo "  Chat:        http://59.46.214.114:18080/chat"
  echo "  WebSocket:   ws://59.46.214.114:18080/msg_gateway"
}

verify_services() {
  wait_for_running mongo "$VERIFY_TIMEOUT_SECONDS"
  wait_for_running redis "$VERIFY_TIMEOUT_SECONDS"
  wait_for_running etcd "$VERIFY_TIMEOUT_SECONDS"
  wait_for_running kafka "$VERIFY_TIMEOUT_SECONDS"
  wait_for_running minio "$VERIFY_TIMEOUT_SECONDS"
  wait_for_healthy openim-server "$VERIFY_TIMEOUT_SECONDS"
  wait_for_healthy openim-chat "$VERIFY_TIMEOUT_SECONDS"
  verify_nginx
  verify_admin_token
  show_runtime_status
}

main() {
  need_root
  ensure_file "$BASE_DIR/$DEPLOY_BUNDLE_NAME"
  ensure_file "$BASE_DIR/$IMAGE_BUNDLE_NAME"
  prepare_files
  run_install
  verify_services
}

main "$@"
