
#!/usr/bin/env bash

#
# Network Workspace Setup
# Supported: Pop!_OS 24.04 / Ubuntu 24.04
#
# Usage:
#   chmod +x ubuntu-network.sh
#   sudo bash ./ubuntu-network.sh
#

set -Eeuo pipefail

readonly PACKAGES=(
    openssh-server
    nmap
    ufw
)

log() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

error() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

# --------------------------------------------------
# Root check
# --------------------------------------------------

if [[ "${EUID}" -ne 0 ]]; then
    error "Run with sudo: sudo bash $0"
fi

# --------------------------------------------------
# OS detection
# --------------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    error "Cannot identify operating system."
fi

source /etc/os-release

case "${ID}" in
    pop|ubuntu)
        log "Detected OS: ${PRETTY_NAME}"
        ;;
    *)
        error "Unsupported OS: ${ID}"
        ;;
esac

if [[ "${VERSION_ID:-}" != "24.04" ]]; then
    warn "This script targets version 24.04."
fi

# --------------------------------------------------
# Package management
# --------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

log "Updating package repositories..."
apt-get update

log "Installing packages..."

apt-get install -y "${PACKAGES[@]}"

# --------------------------------------------------
# SSH configuration
# --------------------------------------------------

log "Configuring SSH..."

systemctl enable ssh
systemctl restart ssh

if ! systemctl is-active --quiet ssh; then
    error "SSH service failed to start."
fi

# --------------------------------------------------
# Firewall configuration
# --------------------------------------------------

log "Configuring UFW..."

# Allow SSH before enabling firewall
ufw allow 22/tcp

# Enable firewall only when inactive
if ! ufw status | grep -q '^Status: active'; then
    ufw --force enable
fi

# --------------------------------------------------
# Verification
# --------------------------------------------------

log "Verifying SSH..."

if ! ss -tln | grep -qE 'LISTEN.*:22([[:space:]]|$)'; then
    error "SSH is not listening on TCP port 22."
fi

log "Verifying Nmap..."

if ! command -v nmap >/dev/null 2>&1; then
    error "Nmap installation failed."
fi

log "Verifying SSH client..."

if ! command -v ssh >/dev/null 2>&1; then
    error "SSH client installation failed."
fi

# --------------------------------------------------
# Summary
# --------------------------------------------------

echo
echo "======================================"
echo " NETWORK WORKSPACE READY"
echo "======================================"

echo
echo "[SSH]"
systemctl is-active ssh
ssh -V 2>&1

echo
echo "[NMAP]"
nmap --version | head -n 2

echo
echo "[FIREWALL]"
ufw status

echo
echo "[LISTENING PORTS]"
ss -tlnp | grep ':22' || true

echo
echo "[CONNECTION]"
echo "ssh <username>@<server-ip>"

echo
log "Setup completed successfully."
