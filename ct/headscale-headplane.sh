#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# MIT License
# Modified by John Evans – Headplane Integration

APP="Headscale"
var_tags="${var_tags:-tailscale}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/headscale ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "headscale" "juanfont/headscale"; then
    msg_info "Stopping headscale"
    systemctl stop headscale
    msg_ok "Stopped headscale"

    fetch_and_deploy_gh_release "headscale" "juanfont/headscale" "binary"

    msg_info "Updating Headplane"
    rm -rf /opt/headplane
    fetch_and_deploy_gh_release "headplane" "tale/headplane" "prebuild" "latest" "/opt/headplane" "headplane.zip"
    chmod +x /opt/headplane/headplane
    msg_ok "Headplane updated"

    msg_info "Starting headscale"
    systemctl enable -q --now headscale
    msg_ok "Started headscale"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_info "Installing dependencies"
apt-get update &>/dev/null
apt-get install -y unzip curl ufw &>/dev/null || true
msg_ok "Dependencies installed"

# ------------------------------------------------------
# Install Headscale
# ------------------------------------------------------
msg_info "Installing Headscale"
fetch_and_deploy_gh_release "headscale" "juanfont/headscale" "binary"
mkdir -p /etc/headscale
msg_ok "Headscale installed"


# ------------------------------------------------------
# Install Headplane
# ------------------------------------------------------
msg_info "Installing Headplane"
mkdir -p /opt/headplane
fetch_and_deploy_gh_release "headplane" "tale/headplane" "prebuild" "latest" "/opt/headplane" "headplane.zip"
chmod +x /opt/headplane/headplane
msg_ok "Headplane installed"


# ------------------------------------------------------
# Headplane environment variables
# ------------------------------------------------------
msg_info "Configuring Headplane environment"

cat << 'EOF' >/etc/default/headplane
# Headplane environment configuration

# Web UI port
HEADPLANE_PORT=80

# Data storage path
HEADPLANE_DATA_PATH="/var/lib/headplane"

# Headscale configuration location
HEADPLANE_HEADSCALE_CONFIG="/etc/headscale"

# TLS (optional)
HEADPLANE_TLS_CERT=""
HEADPLANE_TLS_KEY=""
EOF

mkdir -p /var/lib/headplane
msg_ok "Environment variables configured"


# ------------------------------------------------------
# Auto-generate Headplane config.yaml
# ------------------------------------------------------
msg_info "Generating Headplane config.yaml"

mkdir -p /etc/headplane

cat << 'EOF' >/etc/headplane/config.yaml
###############################################
# Headplane Auto-Generated Configuration File #
###############################################

port: ${HEADPLANE_PORT}
data_path: "${HEADPLANE_DATA_PATH}"
headscale_config: "${HEADPLANE_HEADSCALE_CONFIG}"

tls:
  cert: "${HEADPLANE_TLS_CERT}"
  key: "${HEADPLANE_TLS_KEY}"
EOF

msg_ok "Headplane config.yaml generated"


# ------------------------------------------------------
# Create systemd service for Headplane
# ------------------------------------------------------
msg_info "Creating systemd service for Headplane"

cat << 'EOF' >/etc/systemd/system/headplane.service
[Unit]
Description=Headplane Web UI
After=network.target

[Service]
EnvironmentFile=-/etc/default/headplane

ExecStart=/opt/headplane/headplane \
    --port ${HEADPLANE_PORT} \
    --config /etc/headplane/config.yaml

WorkingDirectory=/opt/headplane
Restart=always
RestartSec=3
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now headplane
msg_ok "Headplane service installed and running"


# ------------------------------------------------------
# Enable Headscale service
# ------------------------------------------------------
msg_info "Enabling Headscale"
systemctl enable --now headscale
msg_ok "Headscale enabled"


# ------------------------------------------------------
# Firewall Rules for Port 80
# ------------------------------------------------------
msg_info "Applying firewall rule for port 80"

if command -v ufw &>/dev/null; then
    ufw allow 80/tcp &>/dev/null || true
    ufw reload &>/dev/null || true
else
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
fi

msg_ok "Firewall rule added: TCP port 80 open"


# ------------------------------------------------------
# Done
# ------------------------------------------------------
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} + Headplane setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access using:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Headscale API: ${IP}/api${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Headplane UI:  http://${IP}/    (port 80)${CL}"
