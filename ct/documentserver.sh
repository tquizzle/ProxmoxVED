#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: TQ (tquinnelly@gmail.com)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Euro-Office/DocumentServer

APP="Euro-Office DocumentServer"
var_tags="${var_tags:-office;documents;collaboration}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/www/onlyoffice/documentserver ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "documentserver" "Euro-Office/DocumentServer"; then
    msg_info "Stopping Services"
    systemctl stop ds-docservice ds-converter ds-metrics
    msg_ok "Stopped Services"

    msg_info "Backing up Configuration"
    cp /etc/onlyoffice/documentserver/local.json /etc/onlyoffice/documentserver/local.json.bak
    msg_ok "Backed up Configuration"

    RELEASE=$(curl -fsSL "https://api.github.com/repos/Euro-Office/DocumentServer/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -fsSL "https://github.com/Euro-Office/DocumentServer/releases/download/${RELEASE}/documentserver_amd64.deb" -o /tmp/documentserver_amd64.deb
    DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/documentserver_amd64.deb &>/dev/null
    rm -f /tmp/documentserver_amd64.deb
    msg_ok "Installed DocumentServer ${RELEASE}"

    msg_info "Restoring Configuration"
    cp /etc/onlyoffice/documentserver/local.json.bak /etc/onlyoffice/documentserver/local.json
    rm -f /etc/onlyoffice/documentserver/local.json.bak
    msg_ok "Restored Configuration"

    msg_info "Starting Services"
    systemctl start ds-docservice ds-converter ds-metrics
    msg_ok "Started Services"
    msg_ok "Updated ${APP} Successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
echo -e "${INFO}${YW} JWT Secret stored in:${CL}"
echo -e "${TAB}${BGN}/etc/onlyoffice/documentserver/local.json${CL}"
