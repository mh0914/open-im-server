#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/deploy.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "deploy env not found: $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

BASE_DIR="${BASE_DIR:-/mnt/im}"
RUNTIME_DIR="${RUNTIME_DIR:-$BASE_DIR/runtime}"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
INSTALLER_DIR="${INSTALLER_DIR:-$BASE_DIR/installers}"
LOCAL_RPM_DIR="${LOCAL_RPM_DIR:-$BASE_DIR/rpms}"
CONFIG_ROOT="$RUNTIME_DIR/config"
STACK_ROOT="$RUNTIME_DIR/stack"
LOG_ROOT="$RUNTIME_DIR/logs"
DATA_ROOT="$RUNTIME_DIR/data"
OPENIM_NETWORK_NAME="${OPENIM_NETWORK_NAME:-openim-net}"
COMPOSE_PROJECT_SERVER="${COMPOSE_PROJECT_SERVER:-openim-server}"
COMPOSE_PROJECT_CHAT="${COMPOSE_PROJECT_CHAT:-openim-chat}"
COMPOSE_PLUGIN_VERSION="${COMPOSE_PLUGIN_VERSION:-v2.35.1}"
COMPOSE_CMD=""

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

pkg_install() {
  case "$PKG_MANAGER" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get install -y "$@"
      ;;
    dnf)
      dnf install -y "$@"
      ;;
    yum)
      yum install -y "$@"
      ;;
  esac
}

try_install_any() {
  local pkg
  for pkg in "$@"; do
    if pkg_install "$pkg"; then
      return 0
    fi
  done
  return 1
}

install_local_rpms_if_present() {
  if [[ ! -d "$LOCAL_RPM_DIR" ]]; then
    return 1
  fi

  shopt -s nullglob
  local rpms=("$LOCAL_RPM_DIR"/*.rpm)
  shopt -u nullglob

  if [[ "${#rpms[@]}" -eq 0 ]]; then
    return 1
  fi

  log "install local rpm packages from $LOCAL_RPM_DIR"
  case "$PKG_MANAGER" in
    dnf)
      dnf install -y "${rpms[@]}"
      ;;
    yum)
      yum install -y "${rpms[@]}"
      ;;
    *)
      return 1
      ;;
  esac
}

install_local_compose_binary_if_present() {
  local arch src plugin_dir

  arch="$(get_arch)"
  plugin_dir="/usr/local/lib/docker/cli-plugins"
  mkdir -p "$plugin_dir"

  for src in \
    "$INSTALLER_DIR/docker-compose-linux-${arch}" \
    "$INSTALLER_DIR/docker-compose" \
    "$INSTALLER_DIR/docker-compose-linux-x86_64"; do
    if [[ -f "$src" ]]; then
      log "install local docker compose plugin from $src"
      cp -f "$src" "$plugin_dir/docker-compose"
      chmod +x "$plugin_dir/docker-compose"
      return 0
    fi
  done

  return 1
}

detect_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    return 0
  fi
  if have_cmd docker-compose; then
    COMPOSE_CMD="docker-compose"
    return 0
  fi
  return 1
}

compose_run() {
  if [[ -z "$COMPOSE_CMD" ]]; then
    detect_compose_cmd || die "docker compose command not found"
  fi

  if [[ "$COMPOSE_CMD" == "docker compose" ]]; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

compose_run_with_env() {
  local env_file="$1"
  shift

  [[ -f "$env_file" ]] || die "compose env file not found: $env_file"

  if [[ -z "$COMPOSE_CMD" ]]; then
    detect_compose_cmd || die "docker compose command not found"
  fi

  if [[ "$COMPOSE_CMD" == "docker compose" ]]; then
    docker compose --env-file "$env_file" "$@"
  else
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
    docker-compose "$@"
  fi
}

detect_pkg_manager() {
  if have_cmd apt-get; then
    PKG_MANAGER="apt"
    return
  fi
  if have_cmd dnf; then
    PKG_MANAGER="dnf"
    return
  fi
  if have_cmd yum; then
    PKG_MANAGER="yum"
    return
  fi
  die "unsupported system: apt-get, dnf, or yum is required"
}

get_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)
      echo "x86_64"
      ;;
    aarch64|arm64)
      echo "aarch64"
      ;;
    *)
      die "unsupported architecture: $arch"
      ;;
  esac
}

ensure_basic_packages() {
  case "$PKG_MANAGER" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y ca-certificates curl tar gzip sed grep coreutils procps findutils
      ;;
    dnf)
      dnf makecache
      dnf install -y ca-certificates curl tar gzip sed grep coreutils procps-ng findutils
      ;;
    yum)
      yum makecache
      yum install -y ca-certificates curl tar gzip sed grep coreutils procps-ng findutils
      ;;
  esac
}

install_docker_compose_fallback() {
  if detect_compose_cmd; then
    return
  fi

  install_local_compose_binary_if_present || true

  if detect_compose_cmd; then
    return
  fi

  case "$PKG_MANAGER" in
    apt)
      try_install_any docker-compose-plugin docker-compose || true
      ;;
    dnf|yum)
      try_install_any docker-compose-plugin docker-compose compose-plugin || true
      ;;
  esac

  if detect_compose_cmd; then
    return
  fi

  local arch plugin_dir url
  arch="$(get_arch)"
  plugin_dir="/usr/local/lib/docker/cli-plugins"
  mkdir -p "$plugin_dir"
  url="https://github.com/docker/compose/releases/download/${COMPOSE_PLUGIN_VERSION}/docker-compose-linux-${arch}"

  curl -fsSI --connect-timeout 10 https://github.com >/dev/null 2>&1 || die "docker compose is unavailable from system packages and github.com is unreachable"
  log "install docker compose plugin from $url"
  curl -fsSL "$url" -o "$plugin_dir/docker-compose"
  chmod +x "$plugin_dir/docker-compose"

  detect_compose_cmd || die "docker compose plugin install failed"
}

install_docker() {
  if [[ "${INSTALL_DOCKER:-1}" != "1" ]]; then
    log "skip docker installation because INSTALL_DOCKER=$INSTALL_DOCKER"
  else
    if have_cmd docker && docker version >/dev/null 2>&1; then
      log "docker already installed"
    else
      install_local_rpms_if_present || true

      case "$PKG_MANAGER" in
        apt)
          try_install_any docker.io docker-ce || true
          ;;
        dnf)
          try_install_any docker docker-engine moby-engine || true
          ;;
        yum)
          try_install_any docker docker-engine moby-engine || true
          ;;
      esac

      if ! have_cmd docker; then
        if [[ -f "$INSTALLER_DIR/get-docker.sh" ]]; then
          log "install docker from local installer $INSTALLER_DIR/get-docker.sh"
          sh "$INSTALLER_DIR/get-docker.sh"
        else
          log "fallback to Docker official convenience script"
          if curl -fsSL --connect-timeout 10 https://get.docker.com -o /tmp/get-docker.sh; then
            sh /tmp/get-docker.sh
          else
            die "docker installation failed from system packages, local installer was not found, and https://get.docker.com is unreachable"
          fi
        fi
      fi
    fi
  fi

  have_cmd docker || die "docker command not found after installation"

  systemctl enable --now docker
  sleep 3
  docker version >/dev/null 2>&1 || die "docker engine is not running normally"

  install_docker_compose_fallback
}

install_nginx() {
  if [[ "${INSTALL_NGINX:-1}" != "1" ]]; then
    log "skip nginx installation because INSTALL_NGINX=$INSTALL_NGINX"
    return
  fi

  if have_cmd nginx; then
    log "nginx already installed"
  else
    install_local_rpms_if_present || true

    case "$PKG_MANAGER" in
      apt)
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y nginx
        ;;
      dnf)
        dnf install -y nginx
        ;;
      yum)
        yum install -y nginx
        ;;
    esac
  fi

  have_cmd nginx || die "nginx command not found after installation"
  systemctl enable --now nginx
}

compute_public_urls() {
  if [[ "${ENABLE_TLS:-0}" == "1" ]]; then
    API_BASE_URL="https://${PUBLIC_HOST}:${PUBLIC_HTTPS_PORT}/api"
    CHAT_BASE_URL="https://${PUBLIC_HOST}:${PUBLIC_HTTPS_PORT}/chat"
    WS_BASE_URL="wss://${PUBLIC_HOST}:${PUBLIC_HTTPS_PORT}/msg_gateway"
    MINIO_EXTERNAL_ADDRESS="https://${PUBLIC_HOST}:${PUBLIC_HTTPS_PORT}/minio"
  else
    API_BASE_URL="http://${PUBLIC_HOST}:${PUBLIC_HTTP_PORT}/api"
    CHAT_BASE_URL="http://${PUBLIC_HOST}:${PUBLIC_HTTP_PORT}/chat"
    WS_BASE_URL="ws://${PUBLIC_HOST}:${PUBLIC_HTTP_PORT}/msg_gateway"
    MINIO_EXTERNAL_ADDRESS="http://${PUBLIC_HOST}:${PUBLIC_HTTP_PORT}/minio"
  fi
}

prepare_runtime_dirs() {
  mkdir -p "$RUNTIME_DIR" "$CONFIG_ROOT" "$STACK_ROOT" "$LOG_ROOT" "$DATA_ROOT"
  mkdir -p "$LOG_ROOT/server" "$LOG_ROOT/chat"
  rm -rf "$CONFIG_ROOT/server" "$CONFIG_ROOT/chat"
  cp -a "$TEMPLATE_DIR/server-config" "$CONFIG_ROOT/server"
  cp -a "$TEMPLATE_DIR/chat-config" "$CONFIG_ROOT/chat"
  cp -f "$TEMPLATE_DIR/openim-server-start-config.yml" "$CONFIG_ROOT/openim-server-start-config.yml"
  cp -f "$TEMPLATE_DIR/openim-chat-start-config.yml" "$CONFIG_ROOT/openim-chat-start-config.yml"

  sed -i "s#^externalAddress:.*#externalAddress: ${MINIO_EXTERNAL_ADDRESS}#" "$CONFIG_ROOT/server/minio.yml"
}

render_server_env() {
  cat >"$STACK_ROOT/server.env" <<EOF
OPENIM_SERVER_IMAGE=${OPENIM_SERVER_IMAGE}
MONGO_IMAGE=${MONGO_IMAGE}
REDIS_IMAGE=${REDIS_IMAGE}
ETCD_IMAGE=${ETCD_IMAGE}
KAFKA_IMAGE=${KAFKA_IMAGE}
MINIO_IMAGE=${MINIO_IMAGE}
DATA_DIR=${DATA_ROOT}
LOG_ROOT=${LOG_ROOT}
CONFIG_ROOT=${CONFIG_ROOT}
TZ=${TZ}
MONGO_INITDB_ROOT_USERNAME=${MONGO_INITDB_ROOT_USERNAME}
MONGO_INITDB_ROOT_PASSWORD=${MONGO_INITDB_ROOT_PASSWORD}
MONGO_DATABASE=${MONGO_DATABASE}
MONGO_USERNAME=${MONGO_USERNAME}
MONGO_PASSWORD=${MONGO_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
ETCD_ROOT_USER=${ETCD_ROOT_USER}
ETCD_ROOT_PASSWORD=${ETCD_ROOT_PASSWORD}
ETCD_USERNAME=${ETCD_USERNAME}
ETCD_PASSWORD=${ETCD_PASSWORD}
MINIO_ACCESS_KEY_ID=${MINIO_ACCESS_KEY_ID}
MINIO_SECRET_ACCESS_KEY=${MINIO_SECRET_ACCESS_KEY}
OPENIM_SECRET=${OPENIM_SECRET}
OPENIM_MSG_GATEWAY_PORT=${OPENIM_MSG_GATEWAY_PORT}
OPENIM_API_PORT=${OPENIM_API_PORT}
MINIO_PORT=${MINIO_PORT}
MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT}
EOF
}

render_server_compose() {
  cat >"$STACK_ROOT/server-compose.yml" <<'EOF'
version: "3.6"

networks:
  openim:
    name: openim-net
    driver: bridge

services:
  mongodb:
    image: "${MONGO_IMAGE}"
    container_name: mongo
    restart: always
    volumes:
      - "${DATA_DIR}/components/mongodb/data/db:/data/db"
      - "${DATA_DIR}/components/mongodb/data/logs:/data/logs"
      - "${DATA_DIR}/components/mongodb/data/conf:/etc/mongo"
    environment:
      TZ: "${TZ}"
      wiredTigerCacheSizeGB: 1
      MONGO_INITDB_ROOT_USERNAME: "${MONGO_INITDB_ROOT_USERNAME}"
      MONGO_INITDB_ROOT_PASSWORD: "${MONGO_INITDB_ROOT_PASSWORD}"
      MONGO_INITDB_DATABASE: "${MONGO_DATABASE}"
      MONGO_OPENIM_USERNAME: "${MONGO_USERNAME}"
      MONGO_OPENIM_PASSWORD: "${MONGO_PASSWORD}"
    command: >
      bash -c '
      docker-entrypoint.sh mongod --wiredTigerCacheSizeGB $$wiredTigerCacheSizeGB --auth &
      until mongosh -u $$MONGO_INITDB_ROOT_USERNAME -p $$MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --eval "db.runCommand({ ping: 1 })" >/dev/null 2>&1; do
        echo "Waiting for MongoDB to start..."
        sleep 1
      done &&
      mongosh -u $$MONGO_INITDB_ROOT_USERNAME -p $$MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --eval "
      db = db.getSiblingDB(\"$$MONGO_INITDB_DATABASE\");
      if (!db.getUser(\"$$MONGO_OPENIM_USERNAME\")) {
        db.createUser({
          user: \"$$MONGO_OPENIM_USERNAME\",
          pwd: \"$$MONGO_OPENIM_PASSWORD\",
          roles: [{role: \"readWrite\", db: \"$$MONGO_INITDB_DATABASE\"}]
        });
      }
      " &&
      tail -f /dev/null
      '
    networks:
      - openim

  redis:
    image: "${REDIS_IMAGE}"
    container_name: redis
    restart: always
    volumes:
      - "${DATA_DIR}/components/redis/data:/data"
    environment:
      TZ: "${TZ}"
    command: >
      redis-server
      --requirepass ${REDIS_PASSWORD}
      --appendonly yes
      --aof-use-rdb-preamble yes
      --save ""
    networks:
      - openim

  etcd:
    image: "${ETCD_IMAGE}"
    container_name: etcd
    restart: always
    environment:
      ETCD_NAME: s1
      ETCD_DATA_DIR: /etcd-data
      ETCD_LISTEN_CLIENT_URLS: http://0.0.0.0:2379
      ETCD_ADVERTISE_CLIENT_URLS: http://0.0.0.0:2379
      ETCD_LISTEN_PEER_URLS: http://0.0.0.0:2380
      ETCD_INITIAL_ADVERTISE_PEER_URLS: http://0.0.0.0:2380
      ETCD_INITIAL_CLUSTER: s1=http://0.0.0.0:2380
      ETCD_INITIAL_CLUSTER_TOKEN: tkn
      ETCD_INITIAL_CLUSTER_STATE: new
      ALLOW_NONE_AUTHENTICATION: "no"
      ETCD_ROOT_USER: "${ETCD_ROOT_USER}"
      ETCD_ROOT_PASSWORD: "${ETCD_ROOT_PASSWORD}"
      ETCD_USERNAME: "${ETCD_USERNAME}"
      ETCD_PASSWORD: "${ETCD_PASSWORD}"
    volumes:
      - "${DATA_DIR}/components/etcd:/etcd-data"
    command: >
      /bin/sh -c '
        etcd &
        export ETCDCTL_API=3
        until etcdctl --endpoints=http://127.0.0.1:2379 endpoint health >/dev/null 2>&1; do
          echo "Waiting for etcd to start..."
          sleep 1
        done
        if [ -n "$${ETCD_ROOT_USER}" ] && [ -n "$${ETCD_ROOT_PASSWORD}" ] && [ -n "$${ETCD_USERNAME}" ] && [ -n "$${ETCD_PASSWORD}" ]; then
          etcdctl --endpoints=http://127.0.0.1:2379 user add $${ETCD_ROOT_USER} --new-user-password=$${ETCD_ROOT_PASSWORD} || true
          etcdctl --endpoints=http://127.0.0.1:2379 user add $${ETCD_USERNAME} --new-user-password=$${ETCD_PASSWORD} || true
          etcdctl --endpoints=http://127.0.0.1:2379 role add openim-role || true
          etcdctl --endpoints=http://127.0.0.1:2379 role grant-permission openim-role --prefix=true readwrite / || true
          etcdctl --endpoints=http://127.0.0.1:2379 role grant-permission openim-role --prefix=true readwrite "" || true
          etcdctl --endpoints=http://127.0.0.1:2379 user grant-role $${ETCD_USERNAME} openim-role || true
          etcdctl --endpoints=http://127.0.0.1:2379 auth enable || true
        fi
        tail -f /dev/null
      '
    networks:
      - openim

  kafka:
    image: "${KAFKA_IMAGE}"
    container_name: kafka
    user: root
    restart: always
    volumes:
      - "${DATA_DIR}/components/kafka:/bitnami/kafka"
    environment:
      TZ: "${TZ}"
      KAFKA_CFG_NODE_ID: 0
      KAFKA_CFG_PROCESS_ROLES: controller,broker
      KAFKA_CFG_CONTROLLER_QUORUM_VOTERS: 0@kafka:9093
      KAFKA_CFG_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_NUM_PARTITIONS: 8
      KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE: "true"
      KAFKA_CFG_LISTENERS: "INTERNAL://:9092,CONTROLLER://:9093,EXTERNAL://:9094"
      KAFKA_CFG_ADVERTISED_LISTENERS: "INTERNAL://kafka:9092,EXTERNAL://127.0.0.1:19094"
      KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP: "CONTROLLER:PLAINTEXT,EXTERNAL:PLAINTEXT,INTERNAL:PLAINTEXT"
      KAFKA_CFG_INTER_BROKER_LISTENER_NAME: INTERNAL
    command: >
      /bin/sh -c '
        exec /opt/bitnami/scripts/kafka/entrypoint.sh /opt/bitnami/scripts/kafka/run.sh
      '
    networks:
      - openim

  minio:
    image: "${MINIO_IMAGE}"
    container_name: minio
    restart: always
    ports:
      - "127.0.0.1:${MINIO_PORT}:9000"
      - "127.0.0.1:${MINIO_CONSOLE_PORT}:9090"
    volumes:
      - "${DATA_DIR}/components/minio/data:/data"
      - "${DATA_DIR}/components/minio/config:/root/.minio"
    environment:
      TZ: "${TZ}"
      MINIO_ROOT_USER: "${MINIO_ACCESS_KEY_ID}"
      MINIO_ROOT_PASSWORD: "${MINIO_SECRET_ACCESS_KEY}"
    command: minio server /data --console-address ":9090"
    networks:
      - openim

  openim-server:
    image: "${OPENIM_SERVER_IMAGE}"
    container_name: openim-server
    restart: always
    depends_on:
      - mongodb
      - redis
      - etcd
      - kafka
      - minio
    entrypoint:
      - bash
      - -c
      - |
        for target in mongo:27017 redis:6379 etcd:2379 kafka:9092 minio:9000; do
          host="$${target%%:*}"
          port="$${target##*:}"
          until </dev/tcp/$$host/$$port; do
            echo "Waiting for $$target ..."
            sleep 2
          done
        done
        mage start
        tail -f /dev/null
    ports:
      - "127.0.0.1:${OPENIM_MSG_GATEWAY_PORT}:10001"
      - "127.0.0.1:${OPENIM_API_PORT}:10002"
    volumes:
      - "${CONFIG_ROOT}/server:/openim-server/config:ro"
      - "${CONFIG_ROOT}/openim-server-start-config.yml:/openim-server/start-config.yml:ro"
      - "${LOG_ROOT}/server:/openim-server/_output/logs"
    ulimits:
      nofile:
        soft: 10000
        hard: 10000
    healthcheck:
      test: ["CMD-SHELL", "mage check >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    networks:
      - openim
EOF
}

render_chat_env() {
  cat >"$STACK_ROOT/chat.env" <<EOF
OPENIM_CHAT_IMAGE=${OPENIM_CHAT_IMAGE}
TZ=${TZ}
CONFIG_ROOT=${CONFIG_ROOT}
LOG_ROOT=${LOG_ROOT}
OPENIM_CHAT_API_PORT=${OPENIM_CHAT_API_PORT}
OPENIM_CHAT_ADMIN_PORT=${OPENIM_CHAT_ADMIN_PORT}
EOF
}

render_chat_compose() {
  cat >"$STACK_ROOT/chat-compose.yml" <<'EOF'
version: "3.6"

services:
  openim-chat:
    image: "${OPENIM_CHAT_IMAGE}"
    container_name: openim-chat
    restart: always
    entrypoint:
      - bash
      - -c
      - |
        for target in mongo:27017 redis:6379 etcd:2379 openim-server:10002; do
          host="$${target%%:*}"
          port="$${target##*:}"
          until </dev/tcp/$$host/$$port; do
            echo "Waiting for $$target ..."
            sleep 2
          done
        done
        mage start
        tail -f /dev/null
    ports:
      - "127.0.0.1:${OPENIM_CHAT_API_PORT}:10008"
      - "127.0.0.1:${OPENIM_CHAT_ADMIN_PORT}:10009"
    volumes:
      - "${CONFIG_ROOT}/chat:/openim-chat/config:ro"
      - "${CONFIG_ROOT}/openim-chat-start-config.yml:/openim-chat/start-config.yml:ro"
      - "${LOG_ROOT}/chat:/openim-chat/_output/logs"
    environment:
      TZ: "${TZ}"
    healthcheck:
      test: ["CMD-SHELL", "mage check >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    networks:
      - openim

networks:
  openim:
    external: true
    name: openim-net
EOF
}

render_nginx_config() {
  local conf
  conf="/etc/nginx/conf.d/openim-public.conf"
  rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true
  rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

  if [[ "${ENABLE_TLS:-0}" == "1" ]]; then
    [[ -f "$SSL_CERT_FILE" ]] || die "SSL cert not found: $SSL_CERT_FILE"
    [[ -f "$SSL_KEY_FILE" ]] || die "SSL key not found: $SSL_KEY_FILE"
    cat >"$conf" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    listen [::]:80;
    server_name _;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://${PUBLIC_HOST}:${PUBLIC_HTTPS_PORT}\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _;

    ssl_certificate     ${SSL_CERT_FILE};
    ssl_certificate_key ${SSL_KEY_FILE};
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    client_max_body_size 200m;
    proxy_connect_timeout 10s;
    proxy_send_timeout 600s;
    proxy_read_timeout 600s;
    proxy_request_buffering off;

    proxy_set_header Host \$http_host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$http_host;
    proxy_set_header X-Forwarded-Port ${PUBLIC_HTTPS_PORT};

    location = / {
        default_type text/plain;
        return 200 "openim nginx ok\\n";
    }

    location = /api { return 301 /api/; }
    location /api/ {
        proxy_http_version 1.1;
        proxy_pass http://127.0.0.1:${OPENIM_API_PORT}/;
    }

    location = /chat { return 301 /chat/; }
    location /chat/ {
        proxy_http_version 1.1;
        proxy_pass http://127.0.0.1:${OPENIM_CHAT_API_PORT}/;
    }

    location = /msg_gateway {
        rewrite ^ / break;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_pass http://127.0.0.1:${OPENIM_MSG_GATEWAY_PORT};
    }

    location /msg_gateway/ {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_pass http://127.0.0.1:${OPENIM_MSG_GATEWAY_PORT}/;
    }

    location = /minio { return 301 /minio/; }
    location /minio/ {
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:${MINIO_PORT}/;
    }
}
EOF
  else
    cat >"$conf" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    listen [::]:80;
    server_name _;

    client_max_body_size 200m;
    proxy_connect_timeout 10s;
    proxy_send_timeout 600s;
    proxy_read_timeout 600s;
    proxy_request_buffering off;

    proxy_set_header Host \$http_host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$http_host;
    proxy_set_header X-Forwarded-Port ${PUBLIC_HTTP_PORT};

    location = / {
        default_type text/plain;
        return 200 "openim nginx ok\\n";
    }

    location = /api { return 301 /api/; }
    location /api/ {
        proxy_http_version 1.1;
        proxy_pass http://127.0.0.1:${OPENIM_API_PORT}/;
    }

    location = /chat { return 301 /chat/; }
    location /chat/ {
        proxy_http_version 1.1;
        proxy_pass http://127.0.0.1:${OPENIM_CHAT_API_PORT}/;
    }

    location = /msg_gateway {
        rewrite ^ / break;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_pass http://127.0.0.1:${OPENIM_MSG_GATEWAY_PORT};
    }

    location /msg_gateway/ {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_pass http://127.0.0.1:${OPENIM_MSG_GATEWAY_PORT}/;
    }

    location = /minio { return 301 /minio/; }
    location /minio/ {
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:${MINIO_PORT}/;
    }
}
EOF
  fi

  nginx -t
  systemctl restart nginx
}

open_firewall_ports() {
  if have_cmd firewall-cmd && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-service=http >/dev/null
    if [[ "${ENABLE_TLS:-0}" == "1" ]]; then
      firewall-cmd --permanent --add-service=https >/dev/null
    fi
    firewall-cmd --reload >/dev/null
  fi
}

load_images() {
  local image_candidates=()
  if [[ -d "$BASE_DIR/images" ]]; then
    while IFS= read -r -d '' file; do image_candidates+=("$file"); done < <(find "$BASE_DIR/images" -maxdepth 1 -type f \( -name '*.tar' -o -name '*.tar.gz' \) -print0 | sort -z)
  fi
  while IFS= read -r -d '' file; do image_candidates+=("$file"); done < <(find "$BASE_DIR" -maxdepth 1 -type f \( -name 'openim-*-images*.tar' -o -name 'openim-*-images*.tar.gz' \) -print0 | sort -z)

  if [[ "${#image_candidates[@]}" -eq 0 ]]; then
    die "no docker image packages found under $BASE_DIR"
  fi

  local seen=()
  local image tmp_dir tmp_tar
  for image in "${image_candidates[@]}"; do
    if printf '%s\n' "${seen[@]}" | grep -Fxq "$image"; then
      continue
    fi
    seen+=("$image")
    log "load image package: $image"
    if [[ "$image" == *.tar.gz ]]; then
      tmp_dir="$(mktemp -d)"
      tmp_tar="$tmp_dir/$(basename "${image%.gz}")"
      gzip -dc "$image" >"$tmp_tar"
      docker load -i "$tmp_tar"
      rm -rf "$tmp_dir"
    else
      docker load -i "$image"
    fi
  done
}

ensure_network() {
  if ! docker network inspect "$OPENIM_NETWORK_NAME" >/dev/null 2>&1; then
    docker network create "$OPENIM_NETWORK_NAME" >/dev/null
  fi
}

deploy_openim() {
  compose_run_with_env "$STACK_ROOT/server.env" -p "$COMPOSE_PROJECT_SERVER" -f "$STACK_ROOT/server-compose.yml" up -d
  compose_run_with_env "$STACK_ROOT/chat.env" -p "$COMPOSE_PROJECT_CHAT" -f "$STACK_ROOT/chat-compose.yml" up -d
}

show_summary() {
  log "deployment completed"
  echo
  echo "OpenIM API:        $API_BASE_URL"
  echo "OpenIM Chat API:   $CHAT_BASE_URL"
  echo "OpenIM WebSocket:  $WS_BASE_URL"
  echo "MinIO External:    $MINIO_EXTERNAL_ADDRESS"
  echo
  echo "Electron env example:"
  echo "VITE_API_URL=$API_BASE_URL"
  echo "VITE_CHAT_URL=$CHAT_BASE_URL"
  echo "VITE_WS_URL=$WS_BASE_URL"
}

main() {
  need_root
  detect_pkg_manager
  ensure_basic_packages
  install_docker
  install_nginx
  compute_public_urls
  prepare_runtime_dirs
  render_server_env
  render_server_compose
  render_chat_env
  render_chat_compose
  load_images
  ensure_network
  render_nginx_config
  open_firewall_ports
  deploy_openim
  show_summary
}

main "$@"
