#!/usr/bin/env bash
#
# 01-host-create-launch-vm.sh
#
# Run this on your HOST machine (the one with VirtualBox installed) to
# download a Rocky Linux ISO, create a VM, and install it completely
# unattended using VirtualBox's built-in "VBoxManage unattended" feature —
# no clicking through the installer. Once it finishes and reboots into the
# desktop, copy 02-guest-provision-rocky.sh into the VM and run it there
# to install all the software and apply hardening.
#
# Always point this at the CURRENT Rocky Linux major version — this script
# tracks Rocky 9 via the "latest" convenience filename Rocky maintains, so
# it stays current automatically within the 9.x line. When Rocky ships a
# new major version (10, 11, ...), bump ROCKY_MAJOR below.
#
# Usage:
#   ./01-host-create-launch-vm.sh
#
# Override any default via environment variables, e.g.:
#   VM_NAME=rocky-devops VM_MEMORY_MB=8192 VM_DISK_MB=61440 ./01-host-create-launch-vm.sh
#
# The install account's password is never put on the command line or left
# on disk: if INSTALL_PASSWORD isn't set in the environment, you'll be
# prompted for it, and it's passed to VBoxManage via a 0600 temp file that
# gets deleted when the script exits.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (override via env vars)
# ---------------------------------------------------------------------------
VM_NAME="${VM_NAME:-rocky-devops}"
VM_MEMORY_MB="${VM_MEMORY_MB:-4096}"
VM_CPUS="${VM_CPUS:-2}"
VM_VRAM_MB="${VM_VRAM_MB:-128}"
VM_DISK_MB="${VM_DISK_MB:-40960}"        # 40 GB
VM_DIR="${VM_DIR:-$HOME/VirtualBox VMs/$VM_NAME}"

ROCKY_MAJOR="${ROCKY_MAJOR:-9}"
# "latest" is a convenience symlink Rocky maintains to the current point
# release, so this stays current without needing a version bump.
ISO_FILENAME="Rocky-${ROCKY_MAJOR}-latest-x86_64-dvd.iso"
ISO_URL="${ISO_URL:-https://download.rockylinux.org/pub/rocky/${ROCKY_MAJOR}/isos/x86_64/${ISO_FILENAME}}"
ISO_DIR="${ISO_DIR:-$HOME/Downloads}"
ISO_PATH="${ISO_DIR}/${ISO_FILENAME}"

# Unattended install answers
INSTALL_USER="${INSTALL_USER:-devops}"
INSTALL_FULL_NAME="${INSTALL_FULL_NAME:-DevOps User}"
INSTALL_HOSTNAME="${INSTALL_HOSTNAME:-$VM_NAME}"
INSTALL_LOCALE="${INSTALL_LOCALE:-en_US}"
INSTALL_COUNTRY="${INSTALL_COUNTRY:-US}"
INSTALL_TIMEZONE="${INSTALL_TIMEZONE:-UTC}"

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$1"; }
die() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
command -v VBoxManage >/dev/null 2>&1 || die \
  "VBoxManage not found. Install VirtualBox first (https://www.virtualbox.org/wiki/Downloads)."

mkdir -p "$ISO_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Get the install password (never echoed, never left on disk, never put on
# the command line where it would show up in `ps`)
# ---------------------------------------------------------------------------
if [[ -z "${INSTALL_PASSWORD:-}" ]]; then
  read -rsp "Set a password for the '$INSTALL_USER' account on the new VM: " INSTALL_PASSWORD
  echo
fi
PASSWORD_FILE="$TMP_DIR/install-password"
umask 077
printf '%s' "$INSTALL_PASSWORD" > "$PASSWORD_FILE"
unset INSTALL_PASSWORD

# ---------------------------------------------------------------------------
# Download + verify the Rocky Linux ISO (skip if already present)
# ---------------------------------------------------------------------------
if [[ -f "$ISO_PATH" ]]; then
  log "ISO already present at $ISO_PATH — skipping download."
else
  log "Downloading $ISO_FILENAME (about 14 GB) ..."
  curl -fL --progress-bar -o "$ISO_PATH" "$ISO_URL" || die \
    "Download failed. Check ISO_URL — verify current filenames at https://download.rockylinux.org/pub/rocky/${ROCKY_MAJOR}/isos/x86_64/"

  log "Verifying checksum ..."
  SUMS_URL="https://download.rockylinux.org/pub/rocky/${ROCKY_MAJOR}/isos/x86_64/CHECKSUM"
  EXPECTED_SUM="$(curl -fsSL "$SUMS_URL" | awk -v f="$ISO_FILENAME" '$0 ~ f && /SHA256/ {print $NF}')"
  if [[ -z "$EXPECTED_SUM" ]]; then
    echo "WARNING: could not find $ISO_FILENAME in CHECKSUM — skipping verification." >&2
  else
    ACTUAL_SUM="$(sha256sum "$ISO_PATH" | awk '{print $1}')"
    [[ "$EXPECTED_SUM" == "$ACTUAL_SUM" ]] || die "Checksum mismatch for $ISO_PATH — re-download and try again."
    log "Checksum OK."
  fi
fi

# ---------------------------------------------------------------------------
# Create the VM (safe to re-run — reuses it if it already exists)
# ---------------------------------------------------------------------------
if VBoxManage list vms | grep -qF "\"$VM_NAME\""; then
  log "VM '$VM_NAME' already exists — skipping creation."
else
  log "Creating VM '$VM_NAME' ..."
  mkdir -p "$VM_DIR"

  # "RedHat_64" is the guest OS type VirtualBox itself auto-detects for
  # Rocky Linux and is guaranteed to exist across VirtualBox versions.
  VBoxManage createvm --name "$VM_NAME" --ostype "RedHat_64" --basefolder "$(dirname "$VM_DIR")" --register

  VBoxManage modifyvm "$VM_NAME" \
    --memory "$VM_MEMORY_MB" \
    --cpus "$VM_CPUS" \
    --vram "$VM_VRAM_MB" \
    --graphicscontroller vmsvga \
    --ioapic on \
    --boot1 disk --boot2 dvd --boot3 none --boot4 none \
    --nic1 nat \
    --audio-driver none \
    --clipboard-mode bidirectional \
    --draganddrop bidirectional \
    --usb-ehci on

  DISK_PATH="$VM_DIR/$VM_NAME.vdi"
  VBoxManage createmedium disk --filename "$DISK_PATH" --size "$VM_DISK_MB" --format VDI

  VBoxManage storagectl "$VM_NAME" --name "SATA Controller" --add sata --controller IntelAhci --portcount 2
  VBoxManage storageattach "$VM_NAME" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$DISK_PATH"

  log "VM '$VM_NAME' created (${VM_MEMORY_MB}MB RAM, ${VM_CPUS} CPUs, ${VM_DISK_MB}MB disk)."
fi

# ---------------------------------------------------------------------------
# Unattended install — VirtualBox generates the kickstart answers, attaches
# the ISO, and boots straight through the install with no clicks.
#
# The auto-generated kickstart's default package selection isn't
# guaranteed to include the GNOME desktop, so --post-install-command
# explicitly installs the Workstation group and sets the graphical target
# as a safety net — belt and suspenders for actually landing on a desktop.
# ---------------------------------------------------------------------------
log "Starting unattended install of Rocky Linux ${ROCKY_MAJOR} ..."
VBoxManage unattended install "$VM_NAME" \
  --iso="$ISO_PATH" \
  --user="$INSTALL_USER" \
  --password-file="$PASSWORD_FILE" \
  --full-user-name="$INSTALL_FULL_NAME" \
  --hostname="$INSTALL_HOSTNAME" \
  --locale="$INSTALL_LOCALE" \
  --country="$INSTALL_COUNTRY" \
  --time-zone="$INSTALL_TIMEZONE" \
  --install-additions \
  --post-install-command="dnf groupinstall -y 'Workstation' && systemctl set-default graphical.target" \
  --start-vm=gui

cat <<EOF

The VM is now installing Rocky Linux completely unattended — just watch
the window, no input needed. The post-install package group install adds
extra time on top of the base install, so this can take 20-30+ minutes.
When it's done it reboots into the desktop; log in as '$INSTALL_USER'
with the password you set.

If the VM powers off instead of rebooting, start it again with:
  VBoxManage startvm "$VM_NAME"

If you land on a text login instead of a desktop, the Workstation group
install in --post-install-command didn't take (e.g. no network during
install) — log in at the text console and run:
  sudo dnf groupinstall -y 'Workstation'
  sudo systemctl set-default graphical.target
  sudo reboot

Next steps:
  1. Log in as '$INSTALL_USER'.
  2. Copy 02-guest-provision-rocky.sh into the VM (drag-and-drop or shared
     clipboard is enabled) and run it as that user:
       chmod +x 02-guest-provision-rocky.sh
       ./02-guest-provision-rocky.sh
EOF
