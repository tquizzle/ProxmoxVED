#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: TQ (tquinnelly@gmail.com)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Euro-Office/DocumentServer

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ── PostgreSQL ─────────────────────────────────────────────────────────────────
PG_VERSION="16" setup_postgresql
PG_DB_NAME="onlyoffice" PG_DB_USER="onlyoffice" setup_postgresql_db

# ── System Dependencies ────────────────────────────────────────────────────────
msg_info "Installing System Dependencies"
echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections
$STD apt install -y \
  gdb \
  curl \
  ca-certificates \
  jq \
  openssl \
  cabextract \
  xfonts-utils \
  redis-server \
  nginx \
  supervisor \
  ttf-mscorefonts-installer
msg_ok "Installed System Dependencies"

# ── RabbitMQ ──────────────────────────────────────────────────────────────────
msg_info "Installing RabbitMQ"
curl -fsSL https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/rabbitmq-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/rabbitmq-archive-keyring.gpg] \
  https://packagecloud.io/rabbitmq/rabbitmq-server/debian/ $(lsb_release -sc) main" \
  >/etc/apt/sources.list.d/rabbitmq.list
$STD apt update
$STD apt install -y rabbitmq-server
systemctl enable -q --now rabbitmq-server
msg_ok "Installed RabbitMQ"

# ── Euro-Office DocumentServer Package ────────────────────────────────────────
msg_info "Installing Euro-Office DocumentServer"
RELEASE=$(curl -fsSL "https://api.github.com/repos/Euro-Office/DocumentServer/releases/latest" \
  | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
curl -fsSL "https://github.com/Euro-Office/DocumentServer/releases/download/${RELEASE}/documentserver_amd64.deb" \
  -o /tmp/documentserver_amd64.deb
DEBIAN_FRONTEND=noninteractive $STD dpkg -i /tmp/documentserver_amd64.deb
$STD apt install -f -y   # resolve any dependency gaps
rm -f /tmp/documentserver_amd64.deb
echo "${RELEASE}" >/opt/documentserver_version.txt
msg_ok "Installed Euro-Office DocumentServer ${RELEASE}"

# ── Configuration ─────────────────────────────────────────────────────────────
msg_info "Configuring DocumentServer"
JWT_SECRET=$(openssl rand -hex 32)
mkdir -p /etc/onlyoffice/documentserver
cat <<EOF >/etc/onlyoffice/documentserver/local.json
{
  "services": {
    "CoAuthoring": {
      "sql": {
        "type": "postgres",
        "dbHost": "localhost",
        "dbPort": 5432,
        "dbName": "${PG_DB_NAME}",
        "dbUser": "${PG_DB_USER}",
        "dbPass": "${PG_DB_PASS}"
      },
      "token": {
        "enable": {
          "request": {
            "inbox": true,
            "outbox": true
          },
          "browser": true
        },
        "inbox": {
          "header": "Authorization",
          "inBody": true
        },
        "outbox": {
          "header": "Authorization",
          "inBody": true
        },
        "secret": {
          "inbox":   { "string": "${JWT_SECRET}" },
          "outbox":  { "string": "${JWT_SECRET}" },
          "session": { "string": "${JWT_SECRET}" }
        }
      }
    }
  },
  "rabbitmq": {
    "url": "amqp://guest:guest@localhost"
  },
  "redis": {
    "host": "127.0.0.1",
    "port": 6379
  }
}
EOF
msg_ok "Configured DocumentServer"

# ── Font Generation ────────────────────────────────────────────────────────────
msg_info "Generating Fonts (this may take a few minutes)"
$STD documentserver-generate-allfonts.sh
msg_ok "Generated Fonts"

# ── Cache Flush ────────────────────────────────────────────────────────────────
msg_info "Flushing Cache"
$STD documentserver-flush-cache.sh -r false
msg_ok "Flushed Cache"

# ── Enable and Start Services ──────────────────────────────────────────────────
msg_info "Starting Services"
systemctl enable -q --now redis-server
systemctl enable -q --now ds-docservice ds-converter ds-metrics
systemctl restart nginx
msg_ok "Started Services"

# ── MOTD / Cleanup ────────────────────────────────────────────────────────────
motd_ssh
customize
cleanup_lxc
