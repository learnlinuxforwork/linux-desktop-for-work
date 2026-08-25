#!/usr/bin/env bash
#
# 02-guest-provision-ubuntu.sh
#
# Run this INSIDE the Ubuntu Desktop VM, as your normal user (NOT via
# sudo/root) after Ubuntu is installed and you're logged into the GNOME
# desktop. It will prompt for your sudo password when needed.
#
#   chmod +x 02-guest-provision-ubuntu.sh
#   ./02-guest-provision-ubuntu.sh
#
# Minimal install: only the applications explicitly requested, everything
# else left at its distro/package default.
#
# What it does, in order:
#   1. Refreshes apt package lists (needed before installing anything)
#   2. Installs devops tooling: AWS CLI v2, Google Cloud CLI, Terraform,
#      OpenTofu, Docker Engine, kubectl
#   3. Installs desktop apps: VS Code, OnlyOffice, Kooha, OBS Studio,
#      Surfshark VPN, VLC, Google Chrome
#   4. Hardens the firewall (ufw)
#   5. Moves the GNOME dock from the side to the bottom of the screen
#   6. Does a final full system update/upgrade

set -euo pipefail

[[ "${EUID}" -eq 0 ]] && { echo "Run this as your normal user, not root/sudo." >&2; exit 1; }

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$1"; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# 1. Refresh package lists + base prerequisites
# ---------------------------------------------------------------------------
log "Updating package index and installing prerequisites"
sudo apt-get update -y
sudo apt-get install -y \
  curl wget gnupg ca-certificates apt-transport-https \
  software-properties-common lsb-release unzip \
  flatpak gnome-software-plugin-flatpak

flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# ---------------------------------------------------------------------------
# 2a. AWS CLI v2
# ---------------------------------------------------------------------------
if ! command -v aws >/dev/null 2>&1; then
  log "Installing AWS CLI v2"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$TMP_DIR/awscliv2.zip"
  unzip -q "$TMP_DIR/awscliv2.zip" -d "$TMP_DIR"
  sudo "$TMP_DIR/aws/install"
else
  log "AWS CLI already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 2b. Google Cloud CLI (gcloud, gsutil, bq)
# ---------------------------------------------------------------------------
if ! command -v gcloud >/dev/null 2>&1; then
  log "Installing Google Cloud CLI"
  sudo install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y google-cloud-cli
else
  log "Google Cloud CLI already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 2c. Terraform
# ---------------------------------------------------------------------------
if ! command -v terraform >/dev/null 2>&1; then
  log "Installing Terraform"
  sudo install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y terraform
else
  log "Terraform already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 2d. OpenTofu (official install script, deb method)
# ---------------------------------------------------------------------------
if ! command -v tofu >/dev/null 2>&1; then
  log "Installing OpenTofu"
  curl -fsSL --proto '=https' --tlsv1.2 https://get.opentofu.org/install-opentofu.sh -o "$TMP_DIR/install-opentofu.sh"
  chmod +x "$TMP_DIR/install-opentofu.sh"
  sudo "$TMP_DIR/install-opentofu.sh" --install-method deb
else
  log "OpenTofu already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 2e. Docker Engine (official repo) — adds current user to the docker group
# ---------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker Engine"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
  echo "NOTE: log out and back in (or 'newgrp docker') for the docker group membership to take effect."
else
  log "Docker already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 2f. kubectl (Kubernetes CLI, pinned stable channel)
# ---------------------------------------------------------------------------
K8S_CHANNEL="${K8S_CHANNEL:-v1.31}"
if ! command -v kubectl >/dev/null 2>&1; then
  log "Installing kubectl ($K8S_CHANNEL channel)"
  sudo install -d -m 0755 /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/deb/Release.key" \
    | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y kubectl
else
  log "kubectl already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 3a. VS Code
# ---------------------------------------------------------------------------
if ! command -v code >/dev/null 2>&1; then
  log "Installing VS Code"
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > "$TMP_DIR/packages.microsoft.gpg"
  sudo install -D -o root -g root -m 644 "$TMP_DIR/packages.microsoft.gpg" /usr/share/keyrings/packages.microsoft.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y code
else
  log "VS Code already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 3b. OnlyOffice Desktop Editors
# ---------------------------------------------------------------------------
if ! dpkg -s onlyoffice-desktopeditors >/dev/null 2>&1; then
  log "Installing OnlyOffice Desktop Editors"
  sudo install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE \
    | sudo gpg --dearmor -o /etc/apt/keyrings/onlyoffice.gpg
  echo "deb [signed-by=/etc/apt/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" \
    | sudo tee /etc/apt/sources.list.d/onlyoffice.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y onlyoffice-desktopeditors
else
  log "OnlyOffice already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 3c. Kooha (screen recorder) via Flatpak/Flathub
# ---------------------------------------------------------------------------
if ! flatpak list --app | grep -q io.github.seadve.Kooha; then
  log "Installing Kooha"
  flatpak install -y flathub io.github.seadve.Kooha
else
  log "Kooha already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 3d. OBS Studio (official PPA)
# ---------------------------------------------------------------------------
if ! command -v obs >/dev/null 2>&1; then
  log "Installing OBS Studio"
  sudo add-apt-repository -y ppa:obsproject/obs-studio
  sudo apt-get update -y
  sudo apt-get install -y obs-studio
else
  log "OBS Studio already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 3e. Surfshark VPN (official installer)
# ---------------------------------------------------------------------------
if ! command -v surfshark-vpn >/dev/null 2>&1; then
  log "Installing Surfshark VPN"
  curl -fsSL https://downloads.surfshark.com/linux/debian-install.sh | sudo sh
  echo "NOTE: run 'surfshark-vpn login' once, interactively, to authenticate."
else
  log "Surfshark VPN already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 3f. VLC
# ---------------------------------------------------------------------------
log "Installing VLC"
sudo apt-get install -y vlc

# ---------------------------------------------------------------------------
# 3g. Google Chrome
# ---------------------------------------------------------------------------
if ! command -v google-chrome >/dev/null 2>&1; then
  log "Installing Google Chrome"
  curl -fsSL -o "$TMP_DIR/google-chrome-stable_current_amd64.deb" \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  sudo apt-get install -y "$TMP_DIR/google-chrome-stable_current_amd64.deb"
else
  log "Google Chrome already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 4. Firewall hardening (ufw)
# ---------------------------------------------------------------------------
log "Hardening firewall (ufw)"
sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit ssh comment 'rate-limit SSH brute force attempts'
sudo ufw logging on
sudo ufw --force enable
sudo ufw status verbose

# ---------------------------------------------------------------------------
# 5. Move the dock from the side to the bottom of the screen
# ---------------------------------------------------------------------------
log "Moving the dock to the bottom of the screen"
gsettings set org.gnome.shell.extensions.dash-to-dock dock-position BOTTOM || \
  echo "WARNING: couldn't set dock-position (are you running this in a GUI session?)"

# ---------------------------------------------------------------------------
# 6. Final full system update/upgrade
# ---------------------------------------------------------------------------
log "Final system update and upgrade"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
sudo apt-get autoremove -y
sudo apt-get autoclean -y

log "Done. A reboot is recommended to finish applying the dock change and any kernel/driver updates."
