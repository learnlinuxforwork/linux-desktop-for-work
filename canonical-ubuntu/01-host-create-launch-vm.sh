#!/usr/bin/env bash
#
# 01-host-create-launch-vm.sh
#
# Run this on your HOST machine (the one with VirtualBox installed) to
# download an Ubuntu Desktop ISO, create a VM, and boot it.
#
# The Ubuntu installer itself is still interactive (VirtualBox does not
# ship an unattended-install button) — you'll click through Ubiquity/
# Subiquity in the VM window once it boots. After Ubuntu is installed and
# you've logged in, copy 02-guest-provision-ubuntu.sh into the VM and run
# it there to install all the software and apply hardening.
#
# Usage:
#   ./01-host-create-launch-vm.sh
#
# Override any default via environment variables, e.g.:
#   VM_NAME=devops-box VM_MEMORY_MB=8192 VM_DISK_MB=61440 ./01-host-create-launch-vm.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (override via env vars)
# ---------------------------------------------------------------------------
VM_NAME="${VM_NAME:-ubuntu-devops}"
VM_MEMORY_MB="${VM_MEMORY_MB:-4096}"
VM_CPUS="${VM_CPUS:-2}"
VM_VRAM_MB="${VM_VRAM_MB:-128}"
VM_DISK_MB="${VM_DISK_MB:-40960}"        # 40 GB
VM_DIR="${VM_DIR:-$HOME/VirtualBox VMs/$VM_NAME}"

UBUNTU_VERSION="${UBUNTU_VERSION:-24.04.3}"
ISO_FILENAME="ubuntu-${UBUNTU_VERSION}-desktop-amd64.iso"
ISO_URL="${ISO_URL:-https://releases.ubuntu.com/24.04/${ISO_FILENAME}}"
ISO_DIR="${ISO_DIR:-$HOME/Downloads}"
ISO_PATH="${ISO_DIR}/${ISO_FILENAME}"

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$1"; }
die() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
command -v VBoxManage >/dev/null 2>&1 || die \
  "VBoxManage not found. Install VirtualBox first (https://www.virtualbox.org/wiki/Downloads)."

mkdir -p "$ISO_DIR"

# ---------------------------------------------------------------------------
# Download + verify the Ubuntu Desktop ISO (skip if already present)
# ---------------------------------------------------------------------------
if [[ -f "$ISO_PATH" ]]; then
  log "ISO already present at $ISO_PATH — skipping download."
else
  log "Downloading $ISO_FILENAME ..."
  curl -fL --progress-bar -o "$ISO_PATH" "$ISO_URL" || die \
    "Download failed. Check UBUNTU_VERSION/ISO_URL — Ubuntu point releases change; verify at https://releases.ubuntu.com/24.04/"

  log "Verifying checksum ..."
  SUMS_URL="https://releases.ubuntu.com/24.04/SHA256SUMS"
  EXPECTED_SUM="$(curl -fsSL "$SUMS_URL" | awk -v f="$ISO_FILENAME" '$2 == "*"f || $2 == f {print $1}')"
  if [[ -z "$EXPECTED_SUM" ]]; then
    echo "WARNING: could not find $ISO_FILENAME in SHA256SUMS — skipping verification." >&2
  else
    ACTUAL_SUM="$(sha256sum "$ISO_PATH" | awk '{print $1}')"
    [[ "$EXPECTED_SUM" == "$ACTUAL_SUM" ]] || die "Checksum mismatch for $ISO_PATH — re-download and try again."
    log "Checksum OK."
  fi
fi

# ---------------------------------------------------------------------------
# Create the VM (idempotent — reuses it if it already exists)
# ---------------------------------------------------------------------------
if VBoxManage list vms | grep -qF "\"$VM_NAME\""; then
  log "VM '$VM_NAME' already exists — skipping creation."
else
  log "Creating VM '$VM_NAME' ..."
  mkdir -p "$VM_DIR"

  VBoxManage createvm --name "$VM_NAME" --ostype "Ubuntu_64" --basefolder "$(dirname "$VM_DIR")" --register

  VBoxManage modifyvm "$VM_NAME" \
    --memory "$VM_MEMORY_MB" \
    --cpus "$VM_CPUS" \
    --vram "$VM_VRAM_MB" \
    --graphicscontroller vmsvga \
    --ioapic on \
    --boot1 dvd --boot2 disk --boot3 none --boot4 none \
    --nic1 nat \
    --audio-driver none \
    --clipboard-mode bidirectional \
    --draganddrop bidirectional \
    --usb-ehci on

  DISK_PATH="$VM_DIR/$VM_NAME.vdi"
  VBoxManage createmedium disk --filename "$DISK_PATH" --size "$VM_DISK_MB" --format VDI

  VBoxManage storagectl "$VM_NAME" --name "SATA Controller" --add sata --controller IntelAhci --portcount 2
  VBoxManage storageattach "$VM_NAME" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$DISK_PATH"

  VBoxManage storagectl "$VM_NAME" --name "IDE Controller" --add ide
  VBoxManage storageattach "$VM_NAME" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium "$ISO_PATH"

  log "VM '$VM_NAME' created (${VM_MEMORY_MB}MB RAM, ${VM_CPUS} CPUs, ${VM_DISK_MB}MB disk)."
fi

# ---------------------------------------------------------------------------
# Boot it
# ---------------------------------------------------------------------------
log "Starting VM '$VM_NAME' ..."
VBoxManage startvm "$VM_NAME" --type gui

cat <<EOF

Next steps:
  1. Walk through the Ubuntu Desktop installer in the VM window.
     For a minimal base OS, choose "Minimal Installation" (not "Normal")
     on the "Updates and other software" screen, and decline third-party
     codecs/drivers unless you need them.
  2. Reboot when it finishes and log in.
  3. Copy 02-guest-provision-ubuntu.sh into the VM (drag-and-drop or shared
     clipboard is enabled) and run it as your normal user:
       chmod +x 02-guest-provision-ubuntu.sh
       ./02-guest-provision-ubuntu.sh
EOF
