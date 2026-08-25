#!/usr/bin/env bash
#
# 02-guest-provision-rocky.sh
#
# Run this INSIDE the Rocky Linux VM, as your normal user (NOT root/sudo),
# after Rocky is installed and you're logged into the GNOME desktop. It
# will prompt for your sudo password when needed.
#
#   chmod +x 02-guest-provision-rocky.sh
#   ./02-guest-provision-rocky.sh
#
# Minimal install: only the applications explicitly requested, everything
# else left at its distro/package default.
#
# What it does, in order:
#   1. Refreshes the dnf package cache (needed before installing anything)
#   2. Installs devops tooling: AWS CLI v2, Google Cloud CLI, Terraform,
#      OpenTofu, Docker Engine, kubectl
#   3. Installs desktop apps: VS Code, OnlyOffice, Kooha, OBS Studio,
#      Surfshark VPN, VLC, Google Chrome
#   4. Hardens the firewall (firewalld)
#   5. Moves the GNOME dock from the side to the bottom of the screen
#   6. Does a final full system update

set -euo pipefail

[[ "${EUID}" -eq 0 ]] && { echo "Run this as your normal user, not root/sudo." >&2; exit 1; }

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$1"; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RHEL_MAJOR="$(rpm -E %rhel)"

# ---------------------------------------------------------------------------
# 1. Refresh package cache + base prerequisites
# ---------------------------------------------------------------------------
log "Refreshing dnf cache and installing prerequisites"
sudo dnf makecache -y
sudo dnf install -y \
  curl wget gnupg2 ca-certificates unzip dnf-plugins-core \
  flatpak

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
  sudo tee /etc/yum.repos.d/google-cloud-sdk.repo >/dev/null <<'EOF'
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
  sudo dnf install -y google-cloud-cli
else
  log "Google Cloud CLI already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 2c. Terraform (HashiCorp official repo)
# ---------------------------------------------------------------------------
if ! command -v terraform >/dev/null 2>&1; then
  log "Installing Terraform"
  sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
  sudo dnf install -y terraform
else
  log "Terraform already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 2d. OpenTofu (official install script, rpm method)
# ---------------------------------------------------------------------------
if ! command -v tofu >/dev/null 2>&1; then
  log "Installing OpenTofu"
  curl -fsSL --proto '=https' --tlsv1.2 https://get.opentofu.org/install-opentofu.sh -o "$TMP_DIR/install-opentofu.sh"
  chmod +x "$TMP_DIR/install-opentofu.sh"
  sudo "$TMP_DIR/install-opentofu.sh" --install-method rpm
else
  log "OpenTofu already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 2e. Docker Engine (official repo) — adds current user to the docker group
# ---------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker Engine"
  sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable --now docker
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
  sudo tee /etc/yum.repos.d/kubernetes.repo >/dev/null <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
  sudo dnf install -y kubectl
else
  log "kubectl already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 3a. VS Code (Microsoft official repo)
# ---------------------------------------------------------------------------
if ! command -v code >/dev/null 2>&1; then
  log "Installing VS Code"
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
  sudo dnf install -y code
else
  log "VS Code already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 3b. OnlyOffice Desktop Editors (official rpm)
# ---------------------------------------------------------------------------
if ! rpm -q onlyoffice-desktopeditors >/dev/null 2>&1; then
  log "Installing OnlyOffice Desktop Editors"
  sudo dnf install -y https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors.x86_64.rpm
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
# 3d. OBS Studio via Flatpak/Flathub
#     (Not in Rocky's own repos — Flathub is the officially recommended
#     source for OBS on RHEL-family distros.)
# ---------------------------------------------------------------------------
if ! flatpak list --app | grep -q com.obsproject.Studio; then
  log "Installing OBS Studio"
  flatpak install -y flathub com.obsproject.Studio
else
  log "OBS Studio already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 3e. Surfshark VPN via Snap
#     (Surfshark doesn't publish an rpm repo; their own support docs point
#     RHEL/Fedora users at Snap. This installs snapd via EPEL first.)
# ---------------------------------------------------------------------------
if ! command -v snap >/dev/null 2>&1; then
  log "Installing snapd (required for Surfshark on Rocky)"
  sudo dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${RHEL_MAJOR}.noarch.rpm"
  sudo dnf install -y snapd
  sudo systemctl enable --now snapd.socket
  sudo ln -sf /var/lib/snapd/snap /snap
  echo "NOTE: log out and back in (or reboot) so snap's PATH entry takes effect before running 'snap install surfshark'."
fi
if command -v snap >/dev/null 2>&1 && ! snap list surfshark >/dev/null 2>&1; then
  log "Installing Surfshark VPN"
  sudo snap install surfshark || echo "NOTE: if this failed because snap's socket just got enabled, log out/in and re-run: sudo snap install surfshark"
else
  command -v snap >/dev/null 2>&1 && log "Surfshark VPN already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 3f. VLC (via RPM Fusion — not in Rocky's own repos due to licensing)
# ---------------------------------------------------------------------------
if ! command -v vlc >/dev/null 2>&1; then
  log "Installing VLC"
  sudo dnf install -y --nogpgcheck "https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-${RHEL_MAJOR}.noarch.rpm"
  sudo dnf install -y --nogpgcheck "https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-${RHEL_MAJOR}.noarch.rpm"
  sudo dnf install -y vlc
else
  log "VLC already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 3g. Google Chrome
# ---------------------------------------------------------------------------
if ! command -v google-chrome >/dev/null 2>&1; then
  log "Installing Google Chrome"
  sudo dnf install -y https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
else
  log "Google Chrome already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 4. Firewall hardening (firewalld)
# ---------------------------------------------------------------------------
log "Hardening firewall (firewalld)"
sudo systemctl enable --now firewalld
sudo firewall-cmd --set-default-zone=public
# Replace the default unlimited SSH allow with a rate-limited one.
sudo firewall-cmd --zone=public --remove-service=ssh --permanent
sudo firewall-cmd --zone=public --add-rich-rule='rule service name="ssh" limit value="10/m" accept' --permanent
sudo firewall-cmd --set-log-denied=all
sudo firewall-cmd --reload
sudo firewall-cmd --list-all

# ---------------------------------------------------------------------------
# 5. Move the dock from the side to the bottom of the screen
# ---------------------------------------------------------------------------
log "Moving the dock to the bottom of the screen"
if ! rpm -q gnome-shell-extension-dash-to-dock >/dev/null 2>&1; then
  sudo dnf install -y gnome-shell-extension-dash-to-dock
fi
gnome-extensions enable dash-to-dock@micxgx.gmail.com 2>/dev/null || true
gsettings set org.gnome.shell.extensions.dash-to-dock dock-position BOTTOM || \
  echo "WARNING: couldn't set dock-position — log out and back in once so the extension loads, then re-run this script."

# ---------------------------------------------------------------------------
# 6. Final full system update
# ---------------------------------------------------------------------------
log "Final system update"
sudo dnf upgrade -y
sudo dnf autoremove -y

log "Done. A reboot is recommended to finish applying the dock change and any kernel/driver updates."
